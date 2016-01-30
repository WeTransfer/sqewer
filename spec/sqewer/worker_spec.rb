require_relative '../spec_helper'

describe Sqewer::Worker, :sqs => true do
  let(:test_logger) {
    $stderr.sync = true
    ENV['SHOW_TEST_LOGS'] ? Logger.new($stderr) : Logger.new(StringIO.new(''))
  }
  
  it 'has all the necessary attributes' do
    attrs = [:logger, :connection, :serializer, :middleware_stack, 
      :execution_context_class, :submitter_class, :isolator, :num_threads]
    default_worker = described_class.default
    attrs.each do | attr_name |
      expect(default_worker).to respond_to(attr_name)
      expect(default_worker.public_send(attr_name)).not_to be_nil
    end
  end
    
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
    worker = described_class.new(logger: test_logger)
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
      
      worker = described_class.new(logger: test_logger)
      
      worker.start
      sleep 2
      worker.stop
    end
  end
  
  context 'when the job cannot be instantiated due to an unknown class' do
    it 'is able to cope with an exception when the job class is unknown (one of generic exceptions)' do
      payload = JSON.dump({job_class: 'UnknownJobClass', arg1: 'some value'})
    
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      
      worker = described_class.new(logger: test_logger)
      
      worker.start
      sleep 2
      worker.stop
      
#      expect(logger_output).to include('uninitialized constant UnknownJobClass')
#      expect(logger_output).to include('Stopping (clean shutdown)')
    end
  end
  
  context 'with a job that spawns another job' do
    it 'sets up the processing pipeline so that jobs can execute in sequence (with threads)' do
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
      
      worker = described_class.new(logger: test_logger, num_threads: 8)
      
      worker.start
      
      begin
        wait_for { File.exist?('initial-job-run') }.to eq(true)
        wait_for { File.exist?('secondary-job-run') }.to eq(true)
        
        File.unlink('initial-job-run')
        File.unlink('secondary-job-run')
      ensure
        worker.stop
      end
    end
    
    it 'sets up the processing pipeline so that jobs can execute in sequence (with processes)' do
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
      
      worker = described_class.new(logger: test_logger, num_threads: 8, isolator: Sqewer::Isolator.process)
      
      worker.start
      
      begin
        wait_for { File.exist?('initial-job-run') }.to eq(true)
        wait_for { File.exist?('secondary-job-run') }.to eq(true)
        
        File.unlink('initial-job-run')
        File.unlink('secondary-job-run')
      ensure
        worker.stop
      end
    end
  end
end