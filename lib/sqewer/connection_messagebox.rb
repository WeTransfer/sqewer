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
  
  class MethodCall < Struct.new(:method_name, :posargs, :kwargs)
    def perform(on)
      if kwargs && posargs
        on.public_send(method_name, *posargs, **kwargs)
      elsif kwargs
        on.public_send(method_name, **kwargs)
      elsif posargs
        on.public_send(method_name, *posargs)
      else
        on.public_send(method_name)
      end
    end
  end
  
  def initialize(connection)
    @connection = connection
    @calls = []
    @mux = Mutex.new
  end
  
  def receive_messages
    @connection.receive_messages
  end
  
  # Saves the given body and the keyword arguments (such as delay_seconds) to be sent into the queue.
  # If there are more sends in the same flush, they will be batched using batched deletes.G
  def send_message(message_body, **kwargs_for_send)
    @mux.synchronize {
      @calls << MethodCall.new(:send_message, [message_body], kwargs_for_send)
    }
  end
  
  # Saves the given identifier to be deleted from the queue. If there are more
  # deletes in the same flush, they will be batched using batched deletes.
  def delete_message(message_identifier)
    @mux.synchronize {
      @calls << MethodCall.new(:delete_message, [message_identifier], nil)
    }
  end
  
  # Flushes all the accumulated commands to the queue connection.
  # First the message sends are going to be flushed, then the message deletes.
  def flush!
    @mux.synchronize do
      sends, others = @calls.partition {|e| e.method_name == :send_message }
      deletes, others = others.partition {|e| e.method_name == :delete_message }
      
      if sends.any?
        @connection.send_multiple_messages do | buffer |
          sends.each { |performable| performable.perform(buffer) }
        end
      end
      
      if deletes.any?
        @connection.delete_multiple_messages do | buffer |
          deletes.each { |performable| performable.perform(buffer) }
        end
      end
      
      others.each do | other |
        other.perform(@connection)
      end
      
      @calls.length.tap { @calls.clear }
    end
  end
end
