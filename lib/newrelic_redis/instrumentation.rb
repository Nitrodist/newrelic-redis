require 'new_relic/agent/method_tracer'

# Redis instrumentation.
#  Originally contributed by Ashley Martens of ngmoco
#  Rewritten, reorganized, and repackaged by Evan Phoenix

DependencyDetection.defer do
  @name = :redis

  METRIC_NAMESPACE = 'External/our.redis.server.com'

  depends_on do
    defined?(::Redis) &&
      !NewRelic::Control.instance['disable_redis'] &&
      ENV['NEWRELIC_ENABLE'].to_s !~ /false|off|no/i
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Redis Instrumentation'
  end

  executes do
    ::Redis::Client.class_eval do
      # Support older versions of Redis::Client that used the method
      # +raw_call_command+.

      call_method = ::Redis::Client.new.respond_to?(:call) ? :call : :raw_call_command

      def call_with_newrelic_trace(*args, &blk)
        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          total_metric = "#{METRIC_NAMESPACE}/allWeb"
        else
          total_metric = "#{METRIC_NAMESPACE}/allOther"
        end

        method_name = args[0].is_a?(Array) ? args[0][0] : args[0]
        metrics = ["#{METRIC_NAMESPACE}/#{method_name.to_s.upcase}", total_metric]

        self.class.trace_execution_scoped(metrics) do
          start = Time.now

          begin
            call_without_newrelic_trace(*args, &blk)
          ensure
            s = NewRelic::Agent.instance.transaction_sampler
            s.notice_nosql(args.inspect, (Time.now - start).to_f) rescue nil
          end
        end
      end

      alias_method :call_without_newrelic_trace, call_method
      alias_method call_method, :call_with_newrelic_trace

      # Older versions of Redis handle pipelining completely differently.
      # Don't bother supporting them for now.
      #
      if public_method_defined? :call_pipelined
        def call_pipelined_with_newrelic_trace(commands, *rest)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            total_metric = "#{METRIC_NAMESPACE}/allWeb"
          else
            total_metric = "#{METRIC_NAMESPACE}/allOther"
          end

          # Report each command as a metric under pipelined, so the user
          # can at least see what all the commands were. This prevents
          # metric namespace explosion.

          metrics = ["#{METRIC_NAMESPACE}/Pipelined", total_metric]

          commands.each do |c|
            name = c.kind_of?(Array) ? c[0] : c
            metrics << "#{METRIC_NAMESPACE}/Pipelined/#{name.to_s.upcase}"
          end

          self.class.trace_execution_scoped(metrics) do
            start = Time.now

            begin
              call_pipelined_without_newrelic_trace commands, *rest
            ensure
              s = NewRelic::Agent.instance.transaction_sampler
              s.notice_nosql(commands.inspect, (Time.now - start).to_f) rescue nil
            end
          end
        end

        alias_method :call_pipelined_without_newrelic_trace, :call_pipelined
        alias_method :call_pipelined, :call_pipelined_with_newrelic_trace
      end
    end
  end

end


