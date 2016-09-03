class Sqewer::TimerHook
  def initialize
    @id = SecureRandom.uuid
    @started = Time.now
    @job_desc = '<unknown>'
  end
  
  def before_demarshal(message_body)
    @job_desc = message_body.to_s[0..32]
  end
  
  def before_execution(job)
    @job_desc = job.inspect
  end

  def register_exception(err)
    delta = Time.now - @started
    Sqewer.logger.error { "[worker] Error in %s after %0.2fs of exec time" % [@job_desc, delta] }
  end
  
  def cleanup
    delta = Time.now - @started
    Sqewer.logger.info { "[worker] Finished %s in %0.2fs" % [@job_desc, delta] }
  end
end