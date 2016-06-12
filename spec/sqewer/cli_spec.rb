require_relative '../spec_helper'

describe Sqewer::CLI, :sqs => true, :wait => {timeout: 120} do
  after :each do
    Dir.glob('*-result').each{|path| File.unlink(path) }
  end
  
  describe 'with a mock Worker' do
    it 'uses just three methods' do
      mock_worker = Class.new do
        def self.start; end
        def self.stop; end
        def self.debug_thread_information!; end
      end
      
      worker_pid = fork do
        Sqewer::CLI.start(mock_worker)
      end
      sleep 1
      
      begin
        Process.kill('INFO', worker_pid) # Calls debug_thread_information!
      rescue ArgumentError, Errno::ENOTSUP # on Linux
      end
      Process.kill('TERM', worker_pid) # Terminates the worker
      
      wait_for { 
        _, status = Process.wait2(worker_pid)
        expect(status.exitstatus).to be_zero # Must have quit cleanly
      }
    end
  end
  
  describe 'runs the commandline app, executes jobs and then quits cleanly' do
    it 'on a USR1 signal' do
      submitter = Sqewer::Connection.default
    
      pid = fork { exec("ruby #{__dir__}/cli_app.rb") }

      Thread.new do
        20.times do
          j = {"_job_class" => 'MyJob', "_job_params" => {first_name: 'John', last_name: 'Doe'}}
          submitter.send_message(JSON.dump(j))
        end
      end

      sleep 8
      wait_for { 
        Process.kill("USR1", pid)
        _, status = Process.wait2(pid)
        expect(status.exitstatus).to be_zero # Must have quit cleanly
      }
      
      generated_files = Dir.glob('*-result')
      expect(generated_files).not_to be_empty
      generated_files.each{|path| File.unlink(path) }
    end
    
    it 'on a TERM signal' do
      submitter = Sqewer::Connection.default
    
      pid = fork { exec("ruby #{__dir__}/cli_app.rb") }

      Thread.new do
        20.times do
          j = {"_job_class" => 'MyJob', "_job_params" => {first_name: 'John', last_name: 'Doe'}}
          submitter.send_message(JSON.dump(j))
        end
      end

      sleep 8
      wait_for { 
        Process.kill("TERM", pid)
        _, status = Process.wait2(pid)
        expect(status.exitstatus).to be_zero # Must have quit cleanly
      }
      
      generated_files = Dir.glob('*-result')
      expect(generated_files).not_to be_empty
      generated_files.each{|path| File.unlink(path) }
    end
  end
end
