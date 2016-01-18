# Adapter that handles communication with a specific queue. In the future this
# could be switched to a Google PubSub queue, or to AMQP, or to any other queue
# with guaranteed re-delivery without ACK. The required queue semantics are
# very simple:
#
# * no message should be deleted if the receiving client has not deleted it explicitly
# * any execution that ends with an exception should cause the message to be re-enqueued
class Sqewer::Connection
  DEFAULT_TIMEOUT_SECONDS = 5
  BATCH_RECEIVE_SIZE = 10
  
  # Returns the default adapter, connected to the queue set via the `SQS_QUEUE_URL`
  # environment variable.
  def self.default
    new(ENV.fetch('SQS_QUEUE_URL'))
  rescue KeyError => e
    raise "SQS_QUEUE_URL not set in the environment. This is the queue URL that the default that Sqewer uses"
  end
  
  # Initializes a new adapter, with access to the SQS queue at the given URL.
  #
  # @param queue_url[String] the SQS queue URL (the URL can be copied from your AWS console)
  def initialize(queue_url)
    require 'aws-sdk'
    @queue_url = queue_url
  end
  
  # Poll for messages, and return if no records are received within the given period.
  #
  # @param timeout[Fixnum] the number of seconds to wait before returning if no messages appear on the queue
  # @yield [String, String] the receipt identifier and contents of the message body
  # @return [void]
  def poll(timeout = DEFAULT_TIMEOUT_SECONDS)
    poller = ::Aws::SQS::QueuePoller.new(@queue_url)
    # SDK v2 automatically deletes messages if the block returns normally, but we want it to happen manually
    # from the caller.
    poller.poll(max_number_of_messages: BATCH_RECEIVE_SIZE, skip_delete: true, 
      idle_timeout: timeout.to_i, wait_time_seconds: timeout.to_i) do | sqs_messages |
      
      sqs_messages.each do | sqs_message |
        yield [sqs_message.receipt_handle, sqs_message.body]
      end
    
    end
  end
  
  # Send a message to the backing queue
  #
  # @param message_body[String] the message to send
  # @param kwargs_for_send[Hash] additional arguments for the submit (such as `delay_seconds`).
  # Passes the arguments to the AWS SDK. 
  # @return [void]
  def send_message(message_body, **kwargs_for_send)
    client = ::Aws::SQS::Client.new
    client.send_message(queue_url: @queue_url, message_body: message_body, **kwargs_for_send)
  end
  
  # Deletes a message after it has been succesfully decoded and processed
  #
  # @param message_identifier[String] the ID of the message to delete. For SQS, it is the receipt handle
  # @return [void]
  def delete_message(message_identifier)
    client = ::Aws::SQS::Client.new
    client.delete_message(queue_url: @queue_url, receipt_handle: message_identifier)
  end
end
