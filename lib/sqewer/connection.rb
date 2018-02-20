# Adapter that handles communication with a specific queue. In the future this
# could be switched to a Google PubSub queue, or to AMQP, or to any other queue
# with guaranteed re-delivery without ACK. The required queue semantics are
# very simple:
#
# * no message should be deleted if the receiving client has not deleted it explicitly
# * any execution that ends with an exception should cause the message to be re-enqueued
class Sqewer::Connection
  DEFAULT_TIMEOUT_SECONDS = 5
  BATCH_SIZE = 10 # Same maximum for send, delete and receive batch
  MAX_RANDOM_FAILURES_PER_CALL = 10
  MAX_RANDOM_RECEIVE_FAILURES = 100 # sure to hit the max_elapsed_time of 900 seconds

  class AwsError < StandardError
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
        wait_time_seconds: DEFAULT_TIMEOUT_SECONDS, max_number_of_messages: BATCH_SIZE)
      response.messages.map do |message|
        Sqewer::Message.new(receipt_handle: message.receipt_handle, body: message.body)
      end
    end
  end

  # Send a message to the backing queue
  #
  # @param messages[Array<Sqewer::Message>] the messages to send
  # @return [void]
  def send_messages(messages)
    in_batches_of(messages, BATCH_SIZE) do |batch|
      params = batch.map{|msg| message_to_send_parameters(msg) }
      handle_batch_with_retries(:send_message_batch, params)
    end
  end

  # Deletes multiple messages after they all have been succesfully decoded and processed.
  #
  # @return [void]
  def delete_messages(messages)
    in_batches_of(messages, BATCH_SIZE) do |batch|
      params = batch.map{|msg| message_to_delete_parameters(msg) }
      handle_batch_with_retries(:delete_message_batch, params)
    end
  end

  private

  def message_to_send_parameters(message)
    {id: message.id, delay_seconds: message.delay_seconds.to_i, message_body: message.body}
  end

  def message_to_delete_parameters(message)
    {id: message.id, receipt_handle: message.receipt_handle}
  end

  def in_batches_of(enum, n)
    batch = []
    enum.each do |item|
      if batch.length >= n
        yield(batch)
        batch.clear
      end
      batch << item
    end
    yield(batch) if batch.any?
  end

  def handle_batch_with_retries(method, batch)
    Retriable.retriable on: [NotOurFaultAwsError, Seahorse::Client::NetworkingError], tries: MAX_RANDOM_FAILURES_PER_CALL do
      resp = client.send(method, queue_url: @queue_url, entries: batch)
      wrong_messages, aws_failures = resp.failed.partition {|m| m.sender_fault }
      if wrong_messages.any?
        err = wrong_messages.inspect + ', ' + resp.inspect
        raise "#{wrong_messages.length} messages failed while doing #{method.to_s} with error: #{err}"
      elsif aws_failures.any?
        # We reset the 'batch' array to only contain the failed messages so only those get retried
        failed_ids = aws_failure_ids.map{|e| e.id.to_s }
        batch = batch.select {|e| failed_ids.include?(e[:id]) }
        raise NotOurFaultAwsError
      end
    end
  end


  def client
    @client ||= Aws::SQS::Client.new
  end
end
