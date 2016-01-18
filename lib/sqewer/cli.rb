module Sqewer::CLI
  # Start the commandline handler, and set up a centralized signal handler that reacts
  # to USR1 and TERM to do a soft-terminate on the worker.
  #
  # @param worker[Sqewer::Worker] the worker to start. Must respond to `#start` and `#stop`
  # @return [void]
  def start(worker = Sqewer::Worker.default)
    # Use a self-pipe to accumulate signals in a central location
    self_read, self_write = IO.pipe
    %w(INT TERM USR1 USR2 TTIN).each do |sig|
      begin
        trap(sig) { self_write.puts(sig) }
      rescue ArgumentError
        # Signal not supported
      end
    end
    
    begin
      worker.start
      # The worker is non-blocking, so in the main CLI process we select() on the signal
      # pipe and handle the signal in a centralized fashion
      while (readable_io = IO.select([self_read]))
        signal = readable_io.first[0].gets.strip
        handle_signal(worker, signal)
      end
    rescue Interrupt
      worker.stop
      exit 1
    end
  end
  
  def handle_signal(worker, sig)
    case sig
    when 'USR1', 'TERM'
      worker.stop
      exit 0
    #when 'TTIN' # a good place to print the worker status
    else
      raise Interrupt
    end
  end
  
  extend self
end
