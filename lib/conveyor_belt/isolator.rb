# Used to isolate the execution environment of the jobs. You can use it to run each
# job in a separate process (a-la Resque) or stick to the default of running those jobs
# in threads (a-la Sidekiq).
class ConveyorBelt::Isolator
  # Used for running each job in a separate process.
  class PerProcess
    # The method called to isolate a particular job flow (both instantiation and execution)
    def isolate
      require 'exceptional_fork'
      ExceptionalFork.fork_and_wait { yield }
    end
  end
    
  # Returns the Isolator that runs each job unserialization and execution
  # as a separate process, and then ensures that that process quits cleanly.
  #
  # @return [ConveyorBelt::Isolator::PerProcess] the isolator
  def self.process
    @per_process ||= PerProcess.new
  end
  
  # Returns the default Isolator that just wraps the instantiation/execution block
  #
  # @return [ConveyorBelt::Isolator] the isolator
  def self.default
    @default ||= new
  end
  
  # The method called to isolate a particular job flow (both instantiation and execution)
  def isolate
    yield
  end
end
