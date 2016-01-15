module ConveyorBelt::CLI
  def self.start(**options_for_worker)
    logger = options_for_worker.fetch(:logger) { Logger.new($stderr) }
    num_threads = options_for_worker.delete(:num_threads) || ENV['THREADS_PER_WORKER'] || 4
    
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
      worker.start(num_threads: num_threads)
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
    logger.info { "Got #{sig}" }
    case sig
    when 'USR1'
      logger.info { 'Received USR1, doing a soft shutdown' }
      worker.stop
      exit 0
    else
      raise Interrupt
    end
      
      #when 'TTIN'
      #  Thread.list.each do |thread|
      #    logger.info { "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}" }
      #    if thread.backtrace
      #      logger.info { thread.backtrace.join("\n") }
      #    else
      #      logger.info { '<no backtrace available>' }
      #    end
      #  end
      #
      #  ready  = launcher.manager.instance_variable_get(:@ready).size
      #  busy   = launcher.manager.instance_variable_get(:@busy).size
      #  queues = launcher.manager.instance_variable_get(:@queues)
      #
      #  logger.info { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{unparse_queues(queues)}" }
  end
end
