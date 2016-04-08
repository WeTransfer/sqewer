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

  AnonymousJobClass = Class.new(StandardError)
  ArityMismatch = Class.new(ArgumentError)

  # Instantiate a Job object from a message body string. If the
  # returned result is `nil`, the job will be skipped.
  #
  # @param message_body[String] a string in JSON containing the job parameters
  # @return [#run, NilClass] an object that responds to `run()` or nil.
  def unserialize(message_body)
    job_ticket_hash = JSON.parse(message_body, symbolize_names: true)
    raise "Job ticket must unmarshal into a Hash" unless job_ticket_hash.is_a?(Hash)

    job_ticket_hash = convert_old_ticket_format(job_ticket_hash) if job_ticket_hash[:job_class]

    # Use fetch() to raise a descriptive KeyError if none
    job_class_name = job_ticket_hash.delete(:_job_class)
    raise ":_job_class not set in the ticket" unless job_class_name
    job_class = Kernel.const_get(job_class_name)

    job_params = job_ticket_hash.delete(:_job_params)
    if job_params.nil? || job_params.empty?
      job_class.new # no args
    else
      begin
        job_class.new(**job_params) # The rest of the message are keyword arguments for the job
      rescue ArgumentError => e
        raise ArityMismatch, "Could not instantiate #{job_class} because it did not accept the arguments #{job_params.inspect}"
      end
    end
  end

  # Converts the given Job into a string, which can be submitted to the queue
  #
  # @param job[#to_h] an object that supports `to_h`
  # @return [String] serialized string ready to be put into the queue
  def serialize(job)
    job_class_name = job.class.to_s

    begin
      Kernel.const_get(job_class_name)
    rescue NameError
      raise AnonymousJobClass, "The class of #{job.inspect} could not be resolved and will not restore to a Job"
    end

    job_params = job.respond_to?(:to_h) ? job.to_h : nil
    job_ticket_hash = {_job_class: job_class_name, _job_params: job_params}
    JSON.dump(job_ticket_hash)
  end

  private

  def convert_old_ticket_format(hash_of_properties)
    job_class = hash_of_properties.delete(:job_class)
    {_job_class: job_class, _job_params: hash_of_properties}
  end
end
