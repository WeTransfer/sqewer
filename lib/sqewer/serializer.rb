# Converts jobs into strings that can be sent to the job queue, and
# restores jobs from those strings. If you want to use, say, Marshal
# to store your jobs instead of the default, or if you want to generate
# custom job objects from S3 bucket notifications, you might want to override this
# class and feed the overridden instance to {Sqewer::Worker}.
class Sqewer::Serializer

  # Returns the default Serializer, of which we store one instance
  # (because the serializer is stateless).
  #
  # @return [Serializer] the instance of the default JSON serializer
  def self.default
    @instance ||= new
  end

  AnonymousJobClass = Class.new(Sqewer::Error)

  # Instantiate a Job object from a message body string. If the
  # returned result is `nil`, the job will be skipped.
  #
  # @param message_body[String] a string in JSON containing the job parameters
  # @return [#run, NilClass] an object that responds to `run()` or nil.
  def unserialize(message_body)
    job_ticket_hash = JSON.parse(message_body, symbolize_names: true)
    raise "Job ticket must unmarshal into a Hash" unless job_ticket_hash.is_a?(Hash)

    # Use fetch() to raise a descriptive KeyError if none
    job_class_name = job_ticket_hash.delete(:_job_class)
    raise ":_job_class not set in the ticket" unless job_class_name
    job_class = Kernel.const_get(job_class_name)

    # Grab the parameter that is responsible for executing the job later. If it is not set,
    # use a default that will put us ahead of that execution deadline from the start.
    t = Time.now.to_i
    execute_after = job_ticket_hash.fetch(:_execute_after) { t - 5 }

    job_params = job_ticket_hash.delete(:_job_params)
    job = if job_params.nil? || job_params.empty?
      job_class.new # no args
    else
      job_class.new(**job_params) # The rest of the message are keyword arguments for the job
    end

    # If the job is not up for execution now, wrap it with something that will
    # re-submit it for later execution when the run() method is called
    return ::Sqewer::Resubmit.new(job, execute_after) if execute_after > t

    job
  end

  # Converts the given Job into a string, which can be submitted to the queue
  #
  # @param job[#to_h] an object that supports `to_h`
  # @param execute_after_timestamp[#to_i, nil] the Unix timestamp after which the job may be executed
  # @return [String] serialized string ready to be put into the queue
  def serialize(job, execute_after_timestamp = nil)
    job_class_name = job.class.to_s

    begin
      Kernel.const_get(job_class_name)
    rescue NameError
      raise AnonymousJobClass, "The class of #{job.inspect} could not be resolved and will not restore to a Job"
    end

    job_params = job.respond_to?(:to_h) ? job.to_h : nil
    job_ticket_hash = {_job_class: job_class_name, _job_params: job_params}
    job_ticket_hash[:_execute_after] = execute_after_timestamp.to_i if execute_after_timestamp

    JSON.dump(job_ticket_hash)
  end
end
