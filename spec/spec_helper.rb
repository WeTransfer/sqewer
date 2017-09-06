$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require 'rspec'
require 'rspec/wait'
require 'dotenv'
require 'aws-sdk-sqs'
require 'simplecov'
require 'securerandom'
Dotenv.load

SimpleCov.start
require 'sqewer'

RSpec.configure do |config| 
  config.order = 'random'
  config.around :each do | example |
    if example.metadata[:sqs]
      queue_name = 'sqewer-test-queue-%s' % SecureRandom.hex(6)
      client = Aws::SQS::Client.new
      resp = client.create_queue(queue_name: queue_name)
      ENV['SQS_QUEUE_URL'] = resp.queue_url
      
      example.run
      
      # Sometimes the queue is already deleted before the example completes. If the test has passed,
      # we do not really care whether this invocation raises an exception about a non-existent queue since
      # all we care about is the queue _being gone_ at the end of the example.
      client.delete_queue(queue_url: ENV.fetch('SQS_QUEUE_URL')) rescue Aws::SQS::Errors::NonExistentQueue
      
      ENV.delete('SQS_QUEUE_URL')
    else
      example.run
    end
  end
end

