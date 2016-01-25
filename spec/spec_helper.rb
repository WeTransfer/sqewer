$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'rspec/wait'
require 'dotenv'
require 'aws-sdk'
require 'simplecov'
Dotenv.load

SimpleCov.start
require 'sqewer'

RSpec.configure do |config| 
  config.order = 'random'
  config.around :each do | example |
    if example.metadata[:sqs]
      queue_name = 'conveyor-belt-test-queue-%s' % SecureRandom.hex(6)
      client = Aws::SQS::Client.new
      resp = client.create_queue(queue_name: queue_name)
      ENV['SQS_QUEUE_URL'] = resp.queue_url
      example.run
      resp = client.delete_queue(queue_url: ENV.fetch('SQS_QUEUE_URL'))
      ENV.delete('SQS_QUEUE_URL')
    else
      example.run
    end
  end
end

