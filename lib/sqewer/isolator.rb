# Used to isolate the execution environment of the jobs. You can use it to run each
# job in a separate process (a-la Resque) or stick to the default of running those jobs
# in threads (a-la Sidekiq).
class Sqewer::Isolator
  # Used for running each job in a separate process.
  class PerProcess < self
    # The method called to isolate a particular job flow (both instantiation and execution)
    #
    # @see {Isolator#perform}
    def perform(*)
      require 'exceptional_fork' unless defined?(ExceptionalFork)
      ExceptionalFork.fork_and_wait { super }
    end
  end
    
  # Returns the Isolator that runs each job unserialization and execution
  # as a separate process, and then ensures that that process quits cleanly.
  #
  # @return [Sqewer::Isolator::PerProcess] the isolator
  def self.process
    @per_process ||= PerProcess.new
  end
  
  # Returns the default Isolator that just wraps the instantiation/execution block
  #
  # @return [Sqewer::Isolator] the isolator
  def self.default
    @default ||= new
  end
  
  # The method called to isolate a particular job flow (both instantiation and execution)
  #
  # @param worker[Sqewer::Worker] the worker that is running the jobs
  # @param message[Sqewer::Connection::Message] the message that is being processed
  def perform(worker, message)
    
    submitter_class, execution_context_class, 
      middleware_stack, connection, serializer, logger = 
        worker.submitter_class, worker.execution_context_class,
          worker.middleware_stack, worker.connection, worker.serializer, worker.logger
    
    job = middleware_stack.around_deserialization(serializer, message.receipt_handle, message.body) do
      serializer.unserialize(message.body)
    end
    return unless job
    
    submitter = submitter_class.new(connection, serializer)
    context = execution_context_class.new(submitter, {'logger' => logger})
    
    t = Time.now
    middleware_stack.around_execution(job, context) do
      job.method(:run).arity.zero? ? job.run : job.run(context)
    end
    logger.info { "[worker] Finished #{job.inspect} in %0.2fs" % (Time.now - t) }
  rescue => e
    logger.error { "[worker] Failed #{job.inspect} with a #{e}" } if job
    raise e
  end
end
