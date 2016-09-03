class Sqewer::Hooks
  def initialize
    @hooks = []
    @hooks << Sqewer::TimerHook.new
    @hooks << Sqewer::AppsignalHook.new
  end
  
  def <<(hook)
    @hooks << hook
  end
  
  def prepare
    @hooks.each do |dep|
      dep.prepare if dep.respond_to?(:prepare)
    end
  end

  def before_demarshal(message_body)
    @hooks.each do |dep|
      dep.before_demarshal(message_body) if dep.respond_to?(:before_demarshal)
    end
  end

  def before_execution(job)
    @hooks.each do |dep|
      dep.before_execution(job) if dep.respond_to?(:before_execution)
    end
  end

  def after_execution(job_to_be_deleted)
    @hooks.each do |dep|
      dep.after_execution(job_to_be_deleted) if dep.respond_to?(:after_execution)
    end
  end

  def register_exception(exception)
    @hooks.each do |dep|
      dep.register_exception(exception) if dep.respond_to?(:register_error)
    end
  end

  def cleanup
    @hooks.each do |dep|
      dep.cleanup if dep.respond_to?(:cleanup)
    end
  end
end

