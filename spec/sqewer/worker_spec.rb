require_relative '../spec_helper'

describe Sqewer::Worker, :sqs => true do
  let(:test_logger) {
    $stderr.sync = true
    ENV['SHOW_TEST_LOGS'] ? Logger.new($stderr) : Logger.new(StringIO.new(''))
  }
  
  it 'supports .default' do
    default_worker = described_class.default
    expect(default_worker).to respond_to(:start)
    expect(default_worker).to respond_to(:stop)
  end
    
  it 'instantiates a new worker object on every call to .default' do
    workers = (1..10).map { described_class.default }
    expect(workers.uniq.length).to eq(10)
  end
  
  it 'can go through the full cycle of initialize, start, stop, start, stop' do
    worker = described_class.new
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
      
      Sqewer.logger = test_logger
      worker = described_class.new
      
      worker.start
      sleep 2
      worker.stop
    end
  end
  
  context 'when the job cannot be instantiated due to an unknown class' do
    it 'is able to cope with an exception when the job class is unknown (one of generic exceptions)' do
      payload = JSON.dump({_job_class: 'UnknownJobClass', _job_params: {arg1: 'some value'}})
    
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      
      Sqewer.logger = test_logger
      worker = described_class.new
      
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
          File.open(File.join(Dir.tmpdir, 'secondary-job-run'),'w') {}
        end
      end
      
      class InitialJob
        def run(executor)
          File.open(File.join(Dir.tmpdir, 'initial-job-run'),'w') {}
          executor.submit!(SecondaryJob.new)
        end
      end
      
      payload = JSON.dump({_job_class: 'InitialJob'})
      client = Aws::SQS::Client.new
      client.send_message(queue_url: ENV.fetch('SQS_QUEUE_URL'), message_body: payload)
      Sqewer.logger = test_logger
      worker = described_class.new(num_threads: 8)
      
      worker.start
      
      begin
        wait_for { File.exist?(File.join(Dir.tmpdir, 'initial-job-run')) }.to eq(true)
        wait_for { File.exist?(File.join(Dir.tmpdir, 'secondary-job-run')) }.to eq(true)
      ensure
        worker.stop
      end
    end
  end
end
