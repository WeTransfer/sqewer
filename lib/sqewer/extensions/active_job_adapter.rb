require 'active_record'

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

        # Runs the contained ActiveJob.
        def run
          if ActiveRecord::Base.connected?
            ActiveRecord::Base.connection_pool.with_connection do
              Base.execute @job.stringify_keys
            end
          else
            Base.execute @job.stringify_keys
          end
        end
      end

      class << self
        def enqueue(active_job) #:nodoc:
          wrapped_job = Performable.from_active_job(active_job)

          Sqewer.submit!(wrapped_job)
        end

        def enqueue_at(active_job, timestamp) #:nodoc:
          wrapped_job = Performable.from_active_job(active_job)

          delta_t = (timestamp - Time.now.to_f).to_i
          raise "Cannot warp time-space and delay the job by #{delta_t}" if delta_t < 0
          raise "Cannot postpone job execution by more than 15 minutes" if delta_t > 900

          Sqewer.submit!(wrapped_job, delay_seconds: delta_t)
        end
      end

    end
  end
end
