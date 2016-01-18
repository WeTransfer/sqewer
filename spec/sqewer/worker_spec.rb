require_relative '../spec_helper'

describe Sqewer::Worker, :sqs => true do
  let(:silent_logger) { Logger.new(StringIO.new('')) }
  
  it 'supports .default' do
    default_worker = described_class.default
    expect(default_worker).to respond_to(:start)
    expect(default_worker).to respond_to(:stop)
  end
    
  it 'instantiates a Logger to STDERR by default' do
    expect(Logger).to receive(:new).with(STDERR)
    worker = described_class.new
  end
  
  it 'can go through the full cycle of initialize, start, stop, start, stop' do
    worker = described_class.new(logger: silent_logger)
    worker.start
    worker.stop
    worker.start
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
      
      worker.start
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
      
      worker.start
      sleep 2
      worker.stop
      
      expect(logger_output).to include('uninitialized constant UnknownJobClass')
      expect(logger_output).to include('Stopping (clean shutdown)')
    end
  end
  
  context 'with a job that spawns another job' do
    it 'sets up the processing pipeline so that jobs can execute in sequence' do
      class SecondaryJob
        def run
          File.open('secondary-job-run','w') {}
        end
      end
      
      class InitialJob
        def run(executor)
          File.open('initial-job-run','w') {}
          executor.submit!(SecondaryJob.new)
        end
      end
      
      payload = JSON.dump({job_class: 'InitialJob'})
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      
      logger_output = ''
      logger_to_string = Logger.new(StringIO.new(logger_output))
      worker = described_class.new(logger: logger_to_string, num_threads: 8)
      
      worker.start
      
      begin
        poll(fail_after: 3) { File.exist?('initial-job-run') }
        poll(fail_after: 3) { File.exist?('secondary-job-run') }
        
        File.unlink('initial-job-run')
        File.unlink('secondary-job-run')
        expect(true).to eq(true)
      ensure
        worker.stop
      end
      
      # Run with a per-process isolator too
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      
      logger_output = ''
      logger_to_string = Logger.new(StringIO.new(logger_output))
      worker = described_class.new(logger: logger_to_string, num_threads: 8, isolator: Sqewer::Isolator.process)
      
      worker.start
      
      begin
        poll(fail_after: 3) { File.exist?('initial-job-run') }
        poll(fail_after: 3) { File.exist?('secondary-job-run') }
        
        File.unlink('initial-job-run')
        File.unlink('secondary-job-run')
        expect(true).to eq(true)
      ensure
        worker.stop
      end
    end
  end
end
