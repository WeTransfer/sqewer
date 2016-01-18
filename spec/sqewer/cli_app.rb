require_relative '../../lib/sqewer'

class MyJob
  include Sqewer::SimpleJob
  attr_accessor :first_name
  attr_accessor :last_name
  
  def run(executor)
    File.open("#{SecureRandom.hex(3)}-result", 'w') {|f| f << [first_name, last_name].join }
  end
end

Sqewer::CLI.start