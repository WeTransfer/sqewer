require_relative '../spec_helper'

describe ConveyorBelt::CLI, :sqs => true do
  it 'runs the commandline app, executes jobs and then quits it using the USR1 signal' do
    submitter = ConveyorBelt::Connection.default
    pid = fork { exec("ruby #{__dir__}/cli_app.rb") }
  
    Thread.new do
      20.times do
        j = {job_class: 'MyJob', first_name: 'John', last_name: 'Doe'}
        submitter.send_message(JSON.dump(j))
      end
    end
   
    sleep 2
    Process.kill("USR1", pid)
    sleep 0.5
    
    generated_files = Dir.glob('*-result')
    expect(generated_files).not_to be_empty
    generated_files.each{|path| File.unlink(path) }
  end
end
