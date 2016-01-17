$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'simplecov'

require 'dotenv'
Dotenv.load

require 'aws-sdk'

SimpleCov.start
require 'conveyor_belt'

module Polling
  # Call the given block every N seconds, and return once the
  # block returns a truthy value. If it still did not return
  # the value after fail_after, fail the spec.
  def poll(every: 0.5, fail_after:, &check_block)
    started_polling = Time.now
    loop do
      return if check_block.call
      sleep(every)
      if (Time.now - started_polling) > fail_after
        fail "Waited for #{fail_after} seconds for the operation to complete but it didnt"
      end
    end
  end
end

RSpec.configure do |config| 
  config.order = 'random'
  config.include Polling
  
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

