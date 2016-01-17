module ConveyorBelt::CLI
  def self.start(**options_for_worker)
    logger = options_for_worker.fetch(:logger) { Logger.new($stderr) }
    
    # Use a self-pipe to accumulate signals in a central location
    self_read, self_write = IO.pipe
    %w(INT TERM USR1 USR2 TTIN).each do |sig|
      begin
        trap(sig) { self_write.puts(sig) }
      rescue ArgumentError
        logger.warn { "Signal #{sig} not supported" }
      end
    end
    
    worker = ConveyorBelt::Worker.new(**options_for_worker)
    begin
      worker.start
      while (readable_io = IO.select([self_read]))
        signal = readable_io.first[0].gets.strip
        handle_signal(worker, logger, signal)
      end
    rescue Interrupt
      worker.stop
      exit 1
    end
  end
  
  def self.handle_signal(worker, logger, sig)
    case sig
    when 'USR1', 'TERM'
      logger.info { 'Received USR1, doing a soft shutdown' }
      worker.stop
      exit 0
    #when 'TTIN' # a good place to print the worker status
    else
      logger.warn { 'Got %s, interrupt' % sig }
      raise Interrupt
    end
  end
end
