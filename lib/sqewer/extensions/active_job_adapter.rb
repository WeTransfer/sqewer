# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
module ActiveJob
  # Only prepend the module with keyword argument acceptance when the version is 4
  # ActiveJob 5.x supports kwargs out of the box
  if ActiveJob::VERSION::MAJOR <= 4
    module Execution
      prepend PerformWithKeywords
    end
  end

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

      def self.enqueue(active_job) #:nodoc:
        wrapped_job = Performable.from_active_job(active_job)

        Sqewer.submit!(wrapped_job)
      end

      def self.enqueue_at(active_job, timestamp) #:nodoc:
        wrapped_job = Performable.from_active_job(active_job)

        delta_t = (timestamp - Time.now.to_i).to_i

        Sqewer.submit!(wrapped_job, delay_seconds: delta_t)
      end

      # ActiveJob in Rails 4 resolves the symbol value you give it
      # and then tries to call enqueue_* methods directly on what
      # got resolved. In Rails 5, first Rails will call .new on
      # what it resolved from the symbol and _then_ call enqueue
      # and enqueue_at on that what has gotten resolved. This means
      # that we have to expose these methods _both_ as class methods
      # and as instance methods.
      # This can be removed when we stop supporting Rails 4.
      def enqueue_at(*args)
        self.class.enqueue_at(*args)
      end
      
      def enqueue(*args)
        self.class.enqueue(*args)
      end
    end
  end
end
