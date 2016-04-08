module Sqewer
  module Contrib
    # Can be used as a wrapper middleware in an ExecutionContext to log exceptions
    # to Appsignal and to monitor performance. Will only activate
    # if the Appsignal gem is loaded within the current process and active.
    class AppsignalWrapper
      # Unserialize the job
      def around_deserialization(serializer, msg_id, msg_payload)
        return yield unless (defined?(Appsignal) && Appsignal.active?)

        Appsignal.monitor_transaction('perform_job.demarshal', 
          :class => serializer.class.to_s, :params => {:recepit_handle => msg_id}, :method => 'deserialize') do
          yield
        end
      end

      # Run the job with Appsignal monitoring.
      def around_execution(job, context)
        return yield unless (defined?(Appsignal) && Appsignal.active?)

        Appsignal.monitor_transaction('perform_job.sqewer', 
          :class => job.class.to_s, :params => job.to_h, :method => 'run') do |t|
            context['appsignal.transaction'] = t
          yield
        end
      end
    end
  end
end
