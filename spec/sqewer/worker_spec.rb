require_relative '../spec_helper'

describe Sqewer::Worker, :sqs => true do
  let(:test_logger) {
    $stderr.sync = true
    ENV['SHOW_TEST_LOGS'] ? Logger.new($stderr) : Logger.new(StringIO.new(''))
  }
  
  it 'has all the necessary attributes' do
    attrs = [:logger, :connection, :serializer, :middleware_stack, 
      :execution_context_class, :submitter_class, :num_threads]
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
    
  it 'instantiates a new worker object on every call to .default' do
    workers = (1..10).map { described_class.default }
    expect(workers.uniq.length).to eq(10)
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
  
  context 'when the connection to SQS hangs in receive_messages' do
    it 'is able to die with dignity' do
      fake_conn = double('Hung connection')
      allow(fake_conn).to receive(:receive_messages) {
        loop { sleep 0.5 }
      }
      worker = described_class.new(logger: test_logger, connection: fake_conn)
      worker.start
      sleep 2
      worker.stop
    end
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
      payload = JSON.dump({_job_class: 'UnknownJobClass', _job_params: {arg1: 'some value'}})
    
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
      
      worker = described_class.new(logger: test_logger, num_threads: 8)
      
      worker.start
      
      begin
        wait_for { File.exist?(File.join(Dir.tmpdir, 'initial-job-run')) }.to eq(true)
        wait_for { File.exist?(File.join(Dir.tmpdir, 'secondary-job-run')) }.to eq(true)
      ensure
        worker.stop
      end
    end
  end

  context 'when a worker thread raises a non-StandardError exception' do
    class CustomFatalException < Exception; end
    
    it 'kills all threads and stops the worker' do
      log_device = StringIO.new('')
      worker = described_class.new(logger: Logger.new(log_device), num_threads: 4)
      allow(worker).to receive(:take_and_execute) do
        if Thread.current[:id] == 2 && Thread.current[:role] == :consumer
          # just for one consumer thread, raise an exception soon after starting
          sleep 1
          raise CustomFatalException, "Custom Fatal Exception"
        else
          # for all the other consumer threads, sleep for a long time to simulate a working thread
          sleep 30
        end
      end
  
      begin
        worker.start

        sleep 5
        consumer_threads = worker.threads.select { |t| t[:role] == :consumer }

        # all the consumer threads should have died by now, as
        # the `Thread.abort_on_exception` flag is set to `true`
        expect(consumer_threads).to all(satisfy { |t| !t.alive? })

        worker.stop
      rescue CustomFatalException
        # expected from a consumer thread, don't fail the test
      end
    end
  end

  context 'when a worker thread raises a StandardError exception' do
    class CustomFatalException < Exception; end
    
    it 'the processing continues' do
      log_device = StringIO.new('')
      worker = described_class.new(logger: Logger.new(log_device), num_threads: 4)
      allow(worker).to receive(:handle_message) do
        if Thread.current[:id] == 2 && Thread.current[:role] == :consumer
          # just for one consumer thread, raise an exception soon after starting
          sleep 1
          raise StandardError
        else
          # for all the other consumer threads, sleep for a long time to simulate a working thread
          sleep 30
        end
      end
  
      worker.start

      sleep 5
      consumer_threads = worker.threads.select { |t| t[:role] == :consumer }

      # all the consumer threads should still be alive
      expect(consumer_threads).to all(satisfy { |t| t.alive? })

      worker.stop
    end
  end
end
