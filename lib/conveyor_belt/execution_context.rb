require 'logger'

class ConveyorBelt::ExecutionContext
  NullLogger = Class.new(Logger).new(nil)
  
  def initialize(params)
    @params = {}.merge!(params)
  end
  
  # Submits one or more jobs to the queue
  def submit!(*jobs, **execution_options)
    @params.fetch('conveyor_belt.connection').submit!(*jobs, **execution_options)
  end
  
  def logger
    @params.fetch('conveyor_belt.logger') { ConveyorBelt::NullLogger }
  end
end
