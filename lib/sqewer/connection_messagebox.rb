require 'thread'

# A recorder for send_message and delete_message calls.
# Will buffer those calls as if it were a Connection, and then execute
# them within a synchronized mutex lock, to prevent concurrent submits
# from the Connection object
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
    @queue = Queue.new
    @mux = Mutex.new
  end
  
  def receive_messages
    @connection.receive_messages
  end
  
  def send_message(message_body, **kwargs_for_send)
    @queue << MethodCall.new(:send_message, [message_body], kwargs_for_send)
  end
  
  def delete_message(message_identifier)
    @queue << MethodCall.new(:delete_message, [message_identifier], nil)
  end
  
  def flush!
    @mux.synchronize do
      executed = 0
      while @queue.length.nonzero?
        @queue.pop.perform(@connection)
        executed += 1
      end
      executed
    end
  end
end
