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

  def submit!(*jobs, delay_seconds: 0)
    sqs_delay, in_job_delay = split_delay(delay_seconds)
    # Pass the actual delay value to the serializer, to be stored in executed_at
    messages = jobs.map do |job|
      body = serializer.serialize(job, Time.now.to_i + in_job_delay)
      Sqewer::Message.new(body: body, delay_seconds: sqs_delay)
    end
    connection.send_messages(messages)
  end

  private

  def split_delay(delay_possibly_higher_than_sqs_max)
    if delay_possibly_higher_than_sqs_max > 899
      [899, delay_possibly_higher_than_sqs_max - 899]
    else
      [delay_possibly_higher_than_sqs_max, 0]
    end
  end

  def clamp_delay(delay)
    [1, 899, delay].sort[1]
  end
end
