# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
module ActiveJob
  module QueueAdapters
    
    # Handle Rails ActiveJob through conveyor_belt.
    # Set it up like so:
    #
    #    Rails.application.config.active_job.queue_adapter = :sqewer
    class SqewerAdapter
      # Works as a Job for sqewer, and wraps an ActiveJob Worker which responds to perform()
      class Performable
        
        # Creates a new Performable using the passed ActiveJob object. The resulting Performable
        # can be sent to any ConveyorBelt queue.
        #
        # @param active_job_worker[ActiveJob::Job] the job you want to convert
        def self.from_active_job(active_job_worker)
          new(worker_class_name: active_job_worker.class.to_s, perform_args: active_job_worker.serialize)
        end
        
        def new(worker_class_name:, perform_args:)
          @worker_class_name = worker_class_name
          @perform_args = perform_args
          # Try to grab the job class immediately, so that an error is raised in the unserializer
          # if the class is not available
          Kernel.const_get(@worker_class_name)
        end
        
        # Runs the contained ActiveJob.
        #
        # @param execution_context[ConveyorBelt::ExecutionContext] the execution context for eventual use
        def run(execution_context)
          Kernel.const_get(@worker_class_name).perform(*@perform_args)
        end
      end
      
      def enqueue(active_job)
        wrapped_job = Performable.from_active_job(active_job)
        
        submitter = ConveyorBelt::Submitter.default
        submitter.submit!(wrapped_job)
        
        #job.provider_job_id = Sidekiq::Client.push \
        #  'class'   => JobWrapper,
        #  'wrapped' => job.class.to_s,
        # 'queue'   => job.queue_name,
        #  'args'    => [ job.serialize ]
      end
      
      def enqueue_at(active_job, timestamp) #:nodoc:
        wrapped_job = Performable.from_active_job(active_job)
        
        delta_t = (timestamp - Time.now).to_i
        raise "Cannot warp time-space and delay the job by #{delta_t}" if delta_t < 0
        raise "Cannot postpone job execution by more than 15 minutes" if delta_t > 900
        
        submitter = ConveyorBelt::Submitter.default
        submitter.submit!(wrapped_job, delay_seconds: delta_t)
        
        #job.provider_job_id = Sidekiq::Client.push \
        # 'class'   => JobWrapper,
        #'wrapped' => job.class.to_s,
        #  'queue'   => job.queue_name,
        #  'args'    => [ job.serialize ],
        #  'at'      => timestamp
      end
    end
  end
end