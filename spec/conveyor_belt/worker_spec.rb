require_relative '../spec_helper'

describe ConveyorBelt::Worker, :sqs => true do
  let(:silent_logger) { Logger.new(StringIO.new('')) }
  
  it 'instantiates a Logger to STDERR by default' do
    expect(Logger).to receive(:new).with(STDERR)
    worker = described_class.new
  end
  
  it 'can go through the full cycle of initialize, start, stop, start, stop' do
    worker = described_class.new(logger: silent_logger)
    worker.start(num_threads: 4)
    sleep 2
    worker.stop
    worker.start
    sleep 1
    worker.stop
  end
  
  it 'raises a state exception if being stopped without being started' do
    worker = described_class.new
    expect {
      worker.stop
    }.to raise_error(/Cannot change state/)
  end
  
  context 'when the job payload cannot be unserialized from JSON due to invalid syntax' do
    it 'is able to cope with an exception when the job class is unknown (one of generic exceptions)' do
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: '{"foo":')
      
      logger_output = ''
      logger_to_string = Logger.new(StringIO.new(logger_output))
    
      worker = described_class.new(logger: logger_to_string)
      
      worker.start(num_threads: 4)
      sleep 2
      worker.stop
      
      expect(logger_output).to include('unexpected token at \'{"foo":')
      expect(logger_output).to include('Stopping (clean shutdown)')
    end
  end
  
  context 'when the job cannot be instantiated due to an unknown class' do
    it 'is able to cope with an exception when the job class is unknown (one of generic exceptions)' do
      payload = JSON.dump({job_class: 'UnknownJobClass', arg1: 'some value'})
    
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      
      logger_output = ''
      logger_to_string = Logger.new(StringIO.new(logger_output))
    
      worker = described_class.new(logger: logger_to_string)
      
      worker.start(num_threads: 4)
      sleep 2
      worker.stop
      
      expect(logger_output).to include('uninitialized constant UnknownJobClass')
      expect(logger_output).to include('Stopping (clean shutdown)')
    end
  end
end