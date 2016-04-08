require 'logger'

# Is passed to each Job when executing (is the argument for the `#run` method
# of the job). The job can use this object to submit extra jobs, or to get
# at the things specific for the execution context (database/key-value store
# connections, error handling transaction and so on).
class Sqewer::ExecutionContext
  # Create a new ExecutionContext with an environment hash.
  #
  # @param submitter[Sqewer::Submitter] the object to submit new jobs through. Used when jobs want to submit jobs
  # @param extra_variables[Hash] any extra data to pass around to each Job
  def initialize(submitter, extra_variables={})
    @submitter = submitter
    @params = {}
    extra_variables.each_pair{|k, v| self[k]  = v }
  end

  # Submits one or more jobs to the queue
  #
  # @see {Sqewer::Submitter#submit!}
  def submit!(job, **execution_options)
    @submitter.submit!(job, **execution_options)
  end

  # Sets a key in the execution environment
  #
  # @param key[#to_s] the key to set
  # @param value the value to set
  def []=(key, value)
    @params[key.to_s] = value
  end

  # Returns a key of the execution environment by name
  #
  # @param key[#to_s] the key to get
  def [](key)
    @params[key.to_s]
  end

  # Returns a key of the execution environment, or executes the given block
  # if the key is not set
  #
  # @param key[#to_s] the key to get
  # @param blk the block to execute if no such key is present
  def fetch(key, &blk)
    @params.fetch(key.to_s, &blk)
  end

  # Returns the logger set in the execution environment, or
  # the NullLogger if no logger is set. Can be used to supply
  # a logger prefixed with job parameters per job.
  #
  # @return [Logger] the logger to send messages to.
  def logger
    @params.fetch('logger') { Sqewer::NullLogger }
  end
end
