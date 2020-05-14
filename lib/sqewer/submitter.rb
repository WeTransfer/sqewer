# A shim for submitting jobs to the queue. Accepts a connection
# (something that responds to `#send_message`)
# and the serializer (something that responds to `#serialize`) to
# convert the job into the string that will be put in the queue.
class Sqewer::Submitter < Struct.new(:connection, :serializer)
  MAX_PERMITTED_MESSAGE_SIZE_BYTES = 256 * 1024

  NotSqewerJob = Class.new(Sqewer::Error)
  MessageTooLarge = Class.new(Sqewer::Error)

  # Returns a default Submitter, configured with the default connection
  # and the default serializer.
  def self.default
    new(Sqewer::Connection.default, Sqewer::Serializer.default)
  end

  def submit!(job, **kwargs_for_send)
    validate_job_responds_to_run!(job)
    message_body = if delay_by_seconds = kwargs_for_send[:delay_seconds]
      clamped_delay = clamp_delay(delay_by_seconds)
      kwargs_for_send[:delay_seconds] = clamped_delay
      # Pass the actual delay value to the serializer, to be stored in executed_at
      serializer.serialize(job, Time.now.to_i + delay_by_seconds)
    else
      serializer.serialize(job)
    end
    validate_message_for_size!(message_body, job)

    connection.send_message(message_body, **kwargs_for_send)
  end

  private

  def validate_job_responds_to_run!(job)
    return if job.respond_to?(:run)
    error_message = "Submitted object is not a valid job (does not respond to #run): #{job.inspect}"
    raise NotSqewerJob.new(error_message)
  end

  def validate_message_for_size!(message_body, job)
    actual_bytesize = message_body.bytesize
    return if actual_bytesize <= MAX_PERMITTED_MESSAGE_SIZE_BYTES
    error_message = "Job #{job.inspect} serialized to a message which was too large (#{actual_bytesize} bytes)"
    raise MessageTooLarge.new(error_message)
  end

  def clamp_delay(delay)
    [1, 899, delay].sort[1]
  end
end
