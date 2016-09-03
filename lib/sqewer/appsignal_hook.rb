class Sqewer::AppsignalHook
  def self.new
    return nil unless defined?(Appsignal) && Appsignal.active?
    super
  end
  
  def initialize
    @transaction = Appsignal::Transaction.create(SecureRandom.uuid, {class: self.class, method: 'initialize'},
      Appsignal::Transaction::BACKGROUND_JOB)
  end
  
  def before_demarshal(message_body)
    @transaction.set_http_or_background_action(class: self.class, method: 'demarshal', body: message_body)
  end
  
  def after_demarshal(job)
    job_params = job.respond_to?(:to_h) ? job.to_h : {}
    @transaction.set_http_or_background_action(class: job.class.to_s, method: 'run', **job_params)
  end 

  def register_exception(e)
    @transaction.set_error(e)
  end
  
  def cleanup
    @transaction.complete
  end
end
