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
    connection.send_message(serializer.serialize(job), **kwargs_for_send)
  end
end
