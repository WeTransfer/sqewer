require 'logger'
require 'thread'
require 'very_tiny_state_machine'
require 'fiber'

# A massively threaded worker engine
class ConveyorBelt::Worker
  DEFAULT_NUM_THREADS = 4
  SLEEP_SECONDS_ON_EMPTY_QUEUE = 1
  THROTTLE_FACTOR = 2
  
  # Returns the default Worker instance, configured based on the default components
  #
  # @return [ConveyorBelt::Worker]
  def self.default
    @default ||= new
  end
  
  # Creates a new Worker. The Worker, unlike it is in the Rails tradition, is only responsible for
  # the actual processing of jobs, and not for the job arguments.
  #
  # @param connection[ConveyorBelt::Connection] the object that handles polling and submitting
  # @param serializer[#serialize, #unserialize] the serializer/unserializer for the jobs
  # @param execution_context_class[Class] the class for the execution context (will be instantiated by 
  # the worker for each job execution)
  # @param submitter_class[Class] the class used for submitting jobs (will be instantiated by the worker for each job execution)
  # @param middleware_stack[ConveyorBelt::MiddlewareStack] the middleware stack that is going to be used
  # @param logger[Logger] the logger to log execution to and to pass to the jobs
  # @param isolator[ConveyorBelt::Isolator] the isolator to encapsulate job instantiation and execution, if desired
  # @param num_threads[Fixnum] how many worker threads to spawn
  def initialize(connection: ConveyorBelt::Connection.default,
      serializer: ConveyorBelt::Serializer.default,
      execution_context_class: ConveyorBelt::ExecutionContext,
      submitter_class: ConveyorBelt::Submitter,
      middleware_stack: ConveyorBelt::MiddlewareStack.default,
      logger: Logger.new($stderr),
      isolator: ConveyorBelt::Isolator.default,
      num_threads: DEFAULT_NUM_THREADS)
    
    @logger = logger
    @connection = connection
    @serializer = serializer
    @middleware_stack = middleware_stack
    @execution_context_class = execution_context_class
    @submitter_class = submitter_class
    @isolator = isolator
    @num_threads = num_threads
    
    raise ArgumentError, "num_threads must be > 0" unless num_threads > 0
    
    @execution_counter = ConveyorBelt::AtomicCounter.new
    
    @state = VeryTinyStateMachine.new(:stopped)
    @state.permit_state :starting, :running, :stopping, :stopped, :failed
    @state.permit_transition :stopped => :starting, :starting => :running, :running => :stopping, :stopping => :stopped
    @state.permit_transition :starting => :failed # Failed to start
  end
  
  # Start listening on the queue, spin up a number of consumer threads that will execute the jobs.
  #
  # @param num_threads[Fixnum] the number of consumer/executor threads to spin up
  # @return [void]
  def start
    @state.transition! :starting
    
    Thread.abort_on_exception = true

    @logger.info { '[worker] Starting with %d consumer threads' % @num_threads }
    @execution_queue = Queue.new
    
    consumers = (1..@num_threads).map do
      Thread.new do
        loop { 
          break if @state.in_state?(:stopping)
          take_and_execute
        }
      end
    end
    
    # Create a fiber-based provider thread. When the execution queue is exhausted, use
    # the fiber to take a new job and place it on the queue. We use a fiber to have a way
    # to "suspend" the polling loop in the SQS client when the local buffer queue fills up.
    provider = Thread.new do
      feeder_fiber = Fiber.new do
        loop do
          break if @state.in_state?(:stopping)
          @connection.poll do |message_id, message_body| 
            break if @state.in_state?(:stopping)
            Fiber.yield([message_id, message_body])
          end
        end
      end
      
      loop do
        break if !feeder_fiber.alive?
        break if stopping?
        
        if @execution_queue.length < (@num_threads * THROTTLE_FACTOR)
          @execution_queue << feeder_fiber.resume
        else
          @logger.debug "Suspending poller (%d items buffered)" % @execution_queue.length
          sleep 0.2
          Thread.pass
        end 
      end
    end
    
    # It makes sense to have one GC caller per process, since a GC cuts across threads.
    # We will perform a full GC cycle after the same number of jobs as our consumer thread
    # count - so not on every job, but still as often as we can to keep the memory use in check.
    gc = Thread.new do
      loop do
        break if stopping?
        GC.start if (@execution_counter.to_i % @num_threads).zero?
        sleep 0.5
      end
    end
    
    @threads = [provider, gc] + consumers
    
    # If any of our threads are already dead, it means there is some misconfiguration and startup failed
    if @threads.any?{|t| !t.alive? }
      @threads.map(&:kill)
      @state.transition! :failed
      @logger.fatal { '[worker] Failed to start (one or more threads died on startup)' }
    else
      @state.transition! :running
      @logger.info { '[worker] Started, %d consumer threads' % consumers.length }
    end
  end
  
  # Attempts to softly stop the running consumers and the producer. Once the call is made,
  # all the threads will stop at their next loop iteration.
  def stop
    @state.transition! :stopping
    @logger.info { '[worker] Stopping (clean shutdown), will wait for threads to terminate'}
    @threads.map(&:join)
    @logger.info { '[worker] Stopped'}
    @state.transition! :stopped
  end
  
  # Peforms a hard shutdown by killing all the threads
  def kill
    @state.transition! :stopping
    @logger.info { '[worker] Killing (unclean shutdown), will kill all threads'}
    @threads.map(&:kill)
    @logger.info { '[worker] Stopped'}
    @state.transition! :stopped
  end
  
  private
  
  def stopping?
    @state.in_state?(:stopping)
  end
  
  
  def take_and_execute
    message_id, message_body = @execution_queue.pop(nonblock=true)
    return unless message_id
    return @connection.delete_message(message_id) unless message_body && !message_body.empty?
    
    @isolator.isolate do
      job = @middleware_stack.around_deserialization(@serializer, message_id, message_body) do
        @serializer.unserialize(message_body)
      end
      
      if job # if the serializer returns a nil or false
        t = Time.now
        submitter = @submitter_class.new(@connection, @serializer)
        context = @execution_context_class.new(submitter, {STR_logger => @logger})
        
        begin
          @middleware_stack.around_execution(job, context) do
            job.method(:run).arity.zero? ? job.run : job.run(context)
          end
          @logger.info { "[worker] Finished #{job.inspect} in %0.2fs" % (Time.now - t) }
        rescue => e
          @logger.error { "[worker] Failed #{job.inspect} with a #{e}" }
          raise e
        end
      end
    end
    
    @connection.delete_message(message_id)
  rescue ThreadError # Queue is empty
    sleep SLEEP_SECONDS_ON_EMPTY_QUEUE
    Thread.pass
  rescue SystemExit, SignalException, Interrupt => e # Time to quit
    @logger.error { "[worker] Signaled, will quit the consumer" }
    return
  rescue => e # anything else, at or below StandardError that does not need us to quit
    @logger.fatal { "[worker] Failed #{message_id} with #{e}" }
    @logger.fatal(e.class)
    @logger.fatal(e.message)
    e.backtrace.each { |s| @logger.fatal{"\t#{s}"} }
  end
  
  STR_logger = 'logger'
end
