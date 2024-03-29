# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
module ActiveJob
  module QueueAdapters
    # Handle Rails ActiveJob through sqewer.
    # Set it up like so:
    #
    #    Rails.application.config.active_job.queue_adapter = :sqewer
    class SqewerAdapter

      # Works as a Job for sqewer, and wraps an ActiveJob Worker which responds to perform()
      class Performable

        # Creates a new Performable using the passed ActiveJob object. The resulting Performable
        # can be sent to any Sqewer queue.
        #
        # @param active_job_worker[ActiveJob::Job] the job you want to convert
        def self.from_active_job(active_job_worker)
          # Try to grab the job class immediately, so that an error is raised in the unserializer
          # if the class is not available
          klass = active_job_worker.class.to_s
          Kernel.const_get(klass)
          new(job: active_job_worker.serialize)
        end

        def initialize(job:)
          @job = job
        end

        def to_h
          {job: @job}
        end

        def inspect
          '<%s>' % [@job.inspect]
        end

        def class_name
          @job[:job_class]
        end

        # Runs the contained ActiveJob.
        def run
          job = ActiveSupport::HashWithIndifferentAccess.new(@job)
          if active_record_defined_and_connected?
            with_active_record_connection_from_pool { Base.execute(job) }
          else
            Base.execute(job)
          end
        end

        private

        def with_active_record_connection_from_pool
          ActiveRecord::Base.connection_pool.with_connection { yield }
        end

        def active_record_defined_and_connected?
          defined?(ActiveRecord) && ActiveRecord::Base.connected?
        end

      end

      def enqueue(*args)
        wrapped_job = Performable.from_active_job(active_job)

        Sqewer.submit!(wrapped_job)
      end

      def enqueue_at(*args)
        wrapped_job = Performable.from_active_job(active_job)

        delta_t = (timestamp - Time.now.to_i).to_i

        Sqewer.submit!(wrapped_job, delay_seconds: delta_t)
      end
    end
  end
end
