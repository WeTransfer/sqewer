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
  MAX_RANDOM_FAILURES_PER_CALL = 10
  MAX_RANDOM_RECEIVE_FAILURES = 100 # sure to hit the max_elapsed_time of 900 seconds

  NotOurFaultAwsError = Class.new(Sqewer::Error)

  # A wrapper for most important properties of the received message
  class Message < Struct.new(:receipt_handle, :body, :attributes)
    def inspect
      body.inspect
    end

    def has_body?
      body && !body.empty?
    end
  end

  # Returns the default adapter, connected to the queue set via the `SQS_QUEUE_URL`
  # environment variable. Switches to SQLite-backed local queue if the SQS_QUEUE_URL
  # is prefixed with 'sqlite3://'
  def self.default
    url_str = ENV.fetch('SQS_QUEUE_URL')
    uri = URI(url_str)
    if uri.scheme == 'sqlite3'
      Sqewer::LocalConnection.new(uri.to_s)
    else
      new(uri.to_s)
    end
  rescue KeyError => e
    raise "SQS_QUEUE_URL not set in the environment. This is the queue URL Sqewer uses by default."
  end

  # Initializes a new adapter, with access to the SQS queue at the given URL.
  #
  # @param queue_url[String] the SQS queue URL (the URL can be copied from your AWS console)
  def initialize(queue_url)
    require 'aws-sdk-sqs'
    @queue_url = queue_url
  end

  # Receive at most 10 messages from the queue, and return the array of Message objects. Retries for at
  # most 900 seconds (15 minutes) and then gives up, thereby crashing the read loop. If SQS is not available
  # even after 15 minutes it is either down or the server is misconfigured. Either way it makes no sense to
  # continue.
  #
  # @return [Array<Message>] an array of Message objects 
  def receive_messages
    Retriable.retriable on: Seahorse::Client::NetworkingError, tries: MAX_RANDOM_RECEIVE_FAILURES do
      response = client.receive_message(queue_url: @queue_url,
        wait_time_seconds: DEFAULT_TIMEOUT_SECONDS, max_number_of_messages: BATCH_RECEIVE_SIZE)
      response.messages.map {|message| Message.new(message.receipt_handle, message.body, message.attributes) }
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

    # each_batch here also needs to ensure that the sum of payload lengths does not exceed 256kb
    def each_batch
      regrouped = pack_into_batches(messages, weight_limit: 256 * 1024, batch_length_limit: 10) do |message|
        message.fetch(:message_body).bytesize
      end
      regrouped.each { |b| yield(b) }
    end

    # Optimizes a large list of items into batches of 10 items
    # or less and with the sum of item lengths being below 256KB
    # The block given to the method should return the weight of the given item
    def pack_into_batches(items, weight_limit:, batch_length_limit:)
      batches = []
      current_batch = []
      current_batch_weight = 0

      # Sort the items by their weight (length of the body).
      sorted_items = items.sort_by { |item| yield(item) }

      # and then take 1 item from the list and append it to the batch if it fits.
      # If it doesn't fit, no item after it will fit into this batch either (!)
      # which is how we can optimize
      sorted_items.each_with_index do |item|
        weight_of_this_item = yield(item)

        # First protect from invalid input
        if weight_of_this_item > weight_limit
          raise "#{item.inspect} was larger than the permissible limit"
        # The first limit is on the item count per batch -
        # if we are limited on that the batch needs to be closed
        elsif current_batch.length == batch_length_limit
          batches << current_batch
          current_batch = []
          current_batch_weight = 0
        # If placing this item in the batch would make the batch overweight
        # we need to close the batch, because all the items which come after
        # this one will be same size or larger. This is the key part of the optimization.
        elsif (current_batch_weight + weight_of_this_item) > weight_limit
          batches << current_batch
          current_batch = []
          current_batch_weight = 0
        end

        # and then append the item to the current batch
        current_batch_weight += weight_of_this_item
        current_batch << item
      end
      batches << current_batch unless current_batch.empty?

      batches
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

    buffer.each_batch {|batch| handle_batch_with_retries(:send_message_batch, batch) }
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

    buffer.each_batch {|batch| handle_batch_with_retries(:delete_message_batch, batch) }
  end

  private

  def handle_batch_with_retries(method, batch)
    Retriable.retriable on: [NotOurFaultAwsError, Seahorse::Client::NetworkingError], tries: MAX_RANDOM_FAILURES_PER_CALL do
      resp = client.send(method, queue_url: @queue_url, entries: batch)
      wrong_messages, aws_failures = resp.failed.partition {|m| m.sender_fault }
      if wrong_messages.any?
        err = wrong_messages.inspect + ', ' + resp.inspect
        raise "#{wrong_messages.length} messages failed while doing #{method.to_s} with error: #{err}"
      elsif aws_failures.any?
        # We set the 'batch' param to an array with only the failed messages so only those get retried
        batch = aws_failures.map {|aws_response_message| batch.find { |m| aws_response_message.id.to_s == m[:id] }}
        raise NotOurFaultAwsError
      end
    end
  end

  def client
    @client ||= Aws::SQS::Client.new(
      instance_profile_credentials_timeout: 1, # defaults to 1 second
      instance_profile_credentials_retries: 5, # defaults to 0 retries
    )
  end
end
