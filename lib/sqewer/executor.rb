class Sqewer::Executor
  def initialize(serializer:, execution_context:, hooks:)
    @context = execution_context
    @serializer = serializer
    @hooks = hooks
  end
  
  def unserialize_and_perform(message_body)
    catch :halt do
      @hooks.prepare
      @hooks.before_demarshal(message_body)
      job = @serializer.unserialize(message_body)
      throw :halt unless job
      @hooks.before_execution(job)
      job.method(:run).arity.zero? ? job.run : job.run(@context)
      @hooks.after_execution(job)
    end
  rescue Exception => e
    @hooks.register_exception(e)
  ensure
    @hooks.cleanup
  end
end
