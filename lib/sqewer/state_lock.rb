require 'delegate'
require 'thread'

# Controls the state of the Worker object, and wraps it's state transitions
# with a Mutex.
class Sqewer::StateLock < SimpleDelegator
  def initialize
    @m = Mutex.new
    m = VeryTinyStateMachine.new(:stopped)
    m.permit_state :starting, :running, :stopping, :stopped, :failed
    m.permit_transition :stopped => :starting, :starting => :running
    m.permit_transition :running => :stopping, :stopping => :stopped
    m.permit_transition :starting => :failed # Failed to start
    __setobj__(m)
  end

  def in_state?(some_state)
    @m.synchronize { __getobj__.in_state?(some_state) }
  end

  def transition!(to_state)
    @m.synchronize { __getobj__.transition!(to_state) }
  end
end
