# A shim for submitting jobs to the queue. Accepts a connection
# (something that responds to `#send_message`)
# and the serializer (something that responds to `#serialize`) to
# convert the job into the string that will be put in the queue.
class Sqewer::Submitter < Struct.new(:connection, :serializer)

  # Returns a default Submitter, configured with the default connection
  # and the default serializer.
  def self.default
    new(Sqewer::Connection.default, Sqewer::Serializer.default)
  end

  def submit!(job, **kwargs_for_send)
    message_body = if delay_by_seconds = kwargs_for_send[:delay_seconds]
      clamped_delay = clamp_delay(delay_by_seconds)
      kwargs_for_send[:delay_seconds] = clamped_delay
      # Pass the actual delay value to the serializer, to be stored in executed_at
      serializer.serialize(job, Time.now.to_i + delay_by_seconds)
    else
      serializer.serialize(job)
    end
    connection.send_message(message_body, **kwargs_for_send)
  end
  
  private
  
  def clamp_delay(delay)
    [1, 899, delay].sort[1]
  end
end
