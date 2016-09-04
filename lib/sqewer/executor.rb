class Sqewer::Executor
  attr_accessor :serializer
  attr_accessor :hooks
  
  def initialize
    @serializer = Sqewer::Serializer.default
    @hooks = Sqewer::Hooks.default
  end
  
  def submit!(job, delay_seconds: 0)
    @submits << [job, delay_seconds]
  end
  
  def unserialize_and_perform(message, send_via_messagebox)
    @submits = []
    catch :halt do
      @hooks.prepare
      @hooks.before_demarshal(message.body)
      job = @serializer.unserialize(message.body)
      throw :halt unless job
      @hooks.before_execution(job)
      job.method(:run).arity.zero? ? job.run : job.run(self)
      @hooks.after_execution(job)
      @submits.each do |job, kwargs_for_send|
        body_to_send = @serializer.serialize(job)
        send_via_messagebox.send_message(body_to_send, **kwargs_for_send)
      end

      # Delete the performed job, and then flush the buffered submits/deletes. If an exception is
      # raised during execution, both deletes _and_ submits will be discarded
      box.delete_message(message.receipt_handle)
      send_via_messagebox.flush!
    end
  rescue Exception => e
    @hooks.register_exception(e)
  ensure
    @hooks.cleanup
  end
end
