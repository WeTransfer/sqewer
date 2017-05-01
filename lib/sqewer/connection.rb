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

  # A wrapper for most important properties of the received message
  class Message < Struct.new(:receipt_handle, :body)
    def inspect
      body.inspect
    end

    def has_body?
      body && !body.empty?
    end
  end

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

  # Receive at most 10 messages from the queue, and return the array of Message objects.
  #
  # @return [Array<Message>] an array of Message objects 
  def receive_messages
    response = client.receive_message(queue_url: @queue_url,
      wait_time_seconds: DEFAULT_TIMEOUT_SECONDS, max_number_of_messages: 10)
    response.messages.map do | message |
      Message.new(message.receipt_handle, message.body)
    end
  end

  # Send a message to the backing queue
  #
  # @param message_body[String] the message to send
  # @param kwargs_for_send[Hash] additional arguments for the submit (such as `delay_seconds`).
  # Passes the arguments to the AWS SDK. 
  # @return [void]
  def send_message(message_body, **kwargs_for_send)
    send_multiple_messages {|via| via.send_message(message_body, **kwargs_for_send) }
  end

  # Stores the messages for the SQS queue (both deletes and sends), and yields them in allowed batch sizes
  class MessageBuffer < Struct.new(:messages)
    MAX_RECORDS = 10
    def initialize
      super([])
    end
    def each_batch
      messages.each_slice(MAX_RECORDS){|batch| yield(batch)}
    end
  end

  # Saves the messages to send to the SQS queue
  class SendBuffer < MessageBuffer
    def send_message(message_body, **kwargs_for_send)
      # The "id" is only valid _within_ the request, and is used when
      # an error response refers to a specific ID within a batch
      m = {message_body: message_body, id: messages.length.to_s}
      m[:delay_seconds] = kwargs_for_send[:delay_seconds] if kwargs_for_send[:delay_seconds]
      messages << m
    end
  end

  # Saves the receipt handles to batch-delete from the SQS queue
  class DeleteBuffer < MessageBuffer
    def delete_message(receipt_handle)
      # The "id" is only valid _within_ the request, and is used when
      # an error response refers to a specific ID within a batch
      m = {receipt_handle: receipt_handle, id: messages.length.to_s}
      messages << m
    end
  end

  # Send multiple messages. If any messages fail to send, an exception will be raised.
  #
  # @yield [#send_message] the object you can send messages through (will be flushed at method return)
  # @return [void]
  def send_multiple_messages
    buffer = SendBuffer.new
    yield(buffer)
    buffer.each_batch do | batch |
      resp = client.send_message_batch(queue_url: @queue_url, entries: batch)
      failed = resp.failed
      if failed.any?
        err = failed[0].message
        raise "%d messages failed to send (first error was %s)" % [failed.length, err]
      end
    end
  end

  # Deletes a message after it has been succesfully decoded and processed
  #
  # @param message_identifier[String] the ID of the message to delete. For SQS, it is the receipt handle
  # @return [void]
  def delete_message(message_identifier)
    delete_multiple_messages {|via| via.delete_message(message_identifier) }
  end

  # Deletes multiple messages after they all have been succesfully decoded and processed.
  #
  # @yield [#delete_message] an object you can delete an individual message through
  # @return [void]
  def delete_multiple_messages
    buffer = DeleteBuffer.new
    yield(buffer)

    buffer.each_batch do | batch |
      resp = client.delete_message_batch(queue_url: @queue_url, entries: batch)
      failed = resp.failed
      if failed.any?
        err = failed.inspect
        raise "%d messages failed to delete (first error was %s)" % [failed.length, err]
      end
    end
  end

  private

  class RetryWrapper < Struct.new(:sqs_client)
    MAX_RETRIES = 1000
    # Provide retrying wrappers for all the methods of Aws::SQS::Client that we actually use
    [:delete_message_batch, :send_message_batch, :receive_message].each do |retriable_method_name|
      define_method(retriable_method_name) do |*args, **kwargs|
        tries = 1
        begin
          sqs_client.public_send(retriable_method_name, *args, **kwargs)
        rescue Seahorse::Client::NetworkingError => e
          if (tries += 1) >= MAX_RETRIES
            raise(e)
          else
            sleep 0.5
            retry
          end
        end
      end
    end
  end

  def client
    @client ||= RetryWrapper.new(Aws::SQS::Client.new)
  end
end
