require_relative '../spec_helper'

describe Sqewer::CLI, :sqs => true, :wait => {timeout: 120} do
  after :each do
    Dir.glob('*-result').each{|path| File.unlink(path) }
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
      Process.kill("USR1", pid)
      wait_for { Process.wait(pid) }
      
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
      Process.kill("TERM", pid)
      wait_for { Process.wait(pid) }
      
      generated_files = Dir.glob('*-result')
      expect(generated_files).not_to be_empty
      generated_files.each{|path| File.unlink(path) }
    end
  end
end
