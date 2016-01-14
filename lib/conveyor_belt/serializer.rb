# Converts jobs into strings that can be sent to the job queue, and
# restores jobs from those strings. If you want to use, say, Marshal
# to store your jobs instead of the default, or if you want to generate
# custom job objects from S3 bucket notifications, you might want to override this
# class and feed the overridden instance to {ConveyorBelt::Worker}.
class ConveyorBelt::Serializer
  
  # Returns the default Serializer, of which we store one instance
  # (because the serializer is stateless).
  #
  # @return [Serializer] the instance of the default JSON serializer
  def self.default
    @instance ||= new
  end
  
  # Instantiate a Job object from a message body string. If the
  # returned result is `nil`, the job will be skipped.
  #
  # @param message_body[String] a string in JSON containing the job parameters
  # @return [#run, NilClass] an object that responds to `run()` or nil.
  def unserialize(message_body)
    job_kwargs = JSON.parse(message_body, symbolize_names: true)
    # Use fetch() to raise a descriptive KeyError if none
    job_class_name = job_kwargs.delete(:job_class)
    raise ":job_class not set in the job arguments" unless job_class_name
    
    job_class = Kernel.const_get(job_class_name)
    job = if message.length > 0
      job_class.new(**message) # The rest of the message are keyword arguments for the job
    else
      job_class.new # no args
    end
  end
  
  # Converts the given Job into a string, which can be submitted to the queue
  #
  # @param job[#to_h] an object that supports `to_h`
  # @return [String] serialized string ready to be put into the queue
  def serialize(job)
    job_ticket_hash = {job_class: job.class.to_s}.merge!(job.to_h)
    JSON.pretty_generate(job_ticket_hash)
  end
end