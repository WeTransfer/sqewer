require 'thread'

# A recorder for send_message and delete_message calls.
# Will buffer those calls as if it were a Connection, and then execute
# them within a synchronized mutex lock, to prevent concurrent submits
# to the Connection object, and, consequently, concurrent calls to the
# SQS client. We also buffer calls to the connection in the messagebox to
# implement simple batching of message submits and deletes. For example,
# imagine your job does this:
#
#     context.submit!(dependent_job)
#     context.submit!(another_dependent_job)
#     # ...100 lines further on
#     context.submit!(yet_another_job)
#
# you would be doing 3 separate SQS requests and spending more money. Whereas
# a messagebox will be able to buffer those sends and pack them in batches,
# consequently performing less requests
class Sqewer::ConnectionMessagebox
  def initialize(connection)
    @connection = connection
    @deletes = []
    @sends = []
    @mux = Mutex.new
  end

  # Saves the given body and the keyword arguments (such as delay_seconds) to be sent into the queue.
  # If there are more sends in the same flush, they will be batched using batched deletes.G
  #
  # @see {Connection#send_message}
  def send_message(message_body, **kwargs_for_send)
    @mux.synchronize {
      @sends << Sqewer::Message.new(body: message_body, **kwargs_for_send)
    }
  end

  # Saves the given identifier to be deleted from the queue. If there are more
  # deletes in the same flush, they will be batched using batched deletes.
  #
  # @see {Connection#delete_message}
  def delete_message(receipt_handle)
    @mux.synchronize {
      @deletes << Sqewer::Message.new(receipt_handle: receipt_handle)
    }
  end

  # Flushes all the accumulated commands to the queue connection.
  # First the message sends are going to be flushed, then the message deletes.
  # All of those will use batching where possible.
  def flush!
    @mux.synchronize do
      @connection.send_messages(@sends)
      @connection.delete_messages(@deletes)
      (@sends.length + @deletes.length).tap { @sends.clear; @deletes.clear }
    end
  end
end
