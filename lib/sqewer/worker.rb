require 'logger'
require 'thread'
require 'very_tiny_state_machine'
require 'fiber'

# A massively threaded worker engine
class Sqewer::Worker
  DEFAULT_NUM_THREADS = 4
  SLEEP_SECONDS_ON_EMPTY_QUEUE = 1
  THROTTLE_FACTOR = 2
  
  # @return [Logger] The logger used for job execution
  attr_reader :logger
  
  # @return [Sqewer::Connection] The connection for sending and receiving messages
  attr_reader :connection
  
  # @return [Sqewer::Serializer] The serializer for unmarshalling and marshalling
  attr_reader :serializer
  
  # @return [Sqewer::MiddlewareStack] The stack used when executing the job
  attr_reader :middleware_stack
  
  # @return [Class] The class to use when instantiating the execution context
  attr_reader :execution_context_class
  
  # @return [Class] The class used to create the Submitter used by jobs to spawn other jobs
  attr_reader :submitter_class
  
  # @return [#perform] The isolator to use when executing each job
  attr_reader :isolator
  
  # @return [Fixnum] the number of threads to spin up
  attr_reader :num_threads
  
  # Returns the default Worker instance, configured based on the default components
  #
  # @return [Sqewer::Worker]
  def self.default
    @default ||= new
  end
  
  # Creates a new Worker. The Worker, unlike it is in the Rails tradition, is only responsible for
  # the actual processing of jobs, and not for the job arguments.
  #
  # @param connection[Sqewer::Connection] the object that handles polling and submitting
  # @param serializer[#serialize, #unserialize] the serializer/unserializer for the jobs
  # @param execution_context_class[Class] the class for the execution context (will be instantiated by 
  # the worker for each job execution)
  # @param submitter_class[Class] the class used for submitting jobs (will be instantiated by the worker for each job execution)
  # @param middleware_stack[Sqewer::MiddlewareStack] the middleware stack that is going to be used
  # @param logger[Logger] the logger to log execution to and to pass to the jobs
  # @param isolator[Sqewer::Isolator] the isolator to encapsulate job instantiation and execution, if desired
  # @param num_threads[Fixnum] how many worker threads to spawn
  def initialize(connection: Sqewer::Connection.default,
      serializer: Sqewer::Serializer.default,
      execution_context_class: Sqewer::ExecutionContext,
      submitter_class: Sqewer::Submitter,
      middleware_stack: Sqewer::MiddlewareStack.default,
      logger: Logger.new($stderr),
      isolator: Sqewer::Isolator.default,
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
    
    @execution_counter = Sqewer::AtomicCounter.new
    
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
          take_and_execute
          break if stopping?
        }
      end
    end
    
    # Create the provider thread. When the execution queue is exhausted,
    # grab new messages and place them on the local queue.
    provider = Thread.new do
      loop do
        break if stopping?
        
        if queue_has_capacity?
          messages = @connection.receive_messages
          if messages.any?
            messages.each {|m| @execution_queue << m }
            @logger.debug { "[worker] Received and buffered %d messages" % messages.length } if messages.any?
          else
            @logger.debug { "[worker] No messages received" }
            Thread.pass
          end
        else
          @logger.debug { "[worker] Suspending poller (%d items buffered)" % @execution_queue.length }
          sleep 1
          Thread.pass
        end 
      end
    end
    
    @threads = consumers + [provider]
    
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
    loop do
      n_live = @threads.select(&:alive?).length
      break if n_live.zero?
      
      n_dead = @threads.length - n_live
      @logger.info {"Waiting on threads to terminate, %d still alive, %d quit" % [n_live, n_dead] }
      
      sleep 2
    end
    
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
  
  def queue_has_capacity?
    @execution_queue.length < (@num_threads * THROTTLE_FACTOR)
  end
  
  def handle_message(message)
    return unless message.receipt_handle
    return @connection.delete_message(message.receipt_handle) unless message.has_body?
    @isolator.perform(self, message)
    # The message delete happens within the Isolator
  end
  
  def take_and_execute
    message = @execution_queue.pop(nonblock=true)
    handle_message(message)
  rescue ThreadError # Queue is empty
    sleep SLEEP_SECONDS_ON_EMPTY_QUEUE
    Thread.pass
  rescue => e # anything else, at or below StandardError that does not need us to quit
    @logger.error { "[worker] Failed %s... with %s: %s" % [message[0..64].inspect, e.class, e.message] }
    e.backtrace.each { |s| @logger.error{"\t#{s}"} }
  end
end
