module Sqewer
  module Contrib
    # Can be used as a wrapper middleware in an ExecutionContext to log exceptions
    # to Appsignal and to monitor performance. Will only activate
    # if the Appsignal gem is loaded within the current process and active.
    class AppsignalWrapper
      def self.new
        if defined?(Appsignal)
          super
        else
          nil
        end
      end

      # extend Appsignal::Hooks::Helpers
      # and use format_args(args) on the jobargs?

      # Acts as a replacement for Appsignal::GenericRequest
      class FakeRequest < Struct.new(:params)
        def initialize; super({}); end
        def env; {params: self.params}; end
      end

      def around_deserialization(serializer, msg_id, msg_payload, msg_attributes)
        return yield unless Appsignal.active?

        # This creates a transaction, but also sets it as the Appsignal.current_transaction
        # which is a thread-local variable. We DO share this middleware between threads,
        # but since the object lives in thread locals it should be fine.
        transaction = Appsignal::Transaction.create(
          SecureRandom.uuid,
          namespace = Appsignal::Transaction::BACKGROUND_JOB,
          request = FakeRequest.new)

        transaction.set_action('%s#%s' % [serializer.class, 'unserialize'])
        transaction.request.params = {:sqs_message_body => msg_payload.to_s}
        if msg_attributes.key?('SentTimestamp')
          transaction.set_queue_start(msg_attributes['SentTimestamp'].to_i)
        end

        job_unserialized = yield

        if !job_unserialized
          # If the job is nil or falsy, we skip the execution. In that case we finish the transaction.
          Appsignal::Transaction.complete_current!
        else
          # If not, then the job will be executed - keep the transaction open for execution block
          # that comes next. Hacky but should work.
          set_transaction_details_from_job(transaction, job_unserialized)
        end
        return job_unserialized
      rescue Exception => e
        if transaction
          # If an exception is raised, raise it through and also set it as the Appsignal exception
          # and commit the transaction.
          transaction.set_error(e)
          Appsignal::Transaction.complete_current!
        end
        raise e
      end

      def set_transaction_details_from_job(transaction, job)
        job_class_string = job.respond_to?(:class_name) ? job.class_name : job.class.to_s
        transaction.set_action('%s#%s' % [job_class_string, 'run'])
        job_params = job.respond_to?(:to_h) ? job.to_h : {}
        transaction.request.params = job_params
      end

      # Run the job with Appsignal monitoring.
      def around_execution(job, context)
        return yield unless Appsignal.active?
        transaction = Appsignal::Transaction.current
        set_transaction_details_from_job(transaction, job)
        yield
      rescue Exception => e
        transaction.set_error(e) if transaction
        raise e
      ensure
        Appsignal::Transaction.complete_current! if transaction
      end
    end
  end
end
