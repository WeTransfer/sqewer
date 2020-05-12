# Allows arbitrary wrapping of the job deserialization and job execution procedures
class Sqewer::MiddlewareStack

  # Returns the default middleware stack, which is empty (an instance of None).
  #
  # @return [MiddlewareStack] the default empty stack
  def self.default
    @instance ||= new
  end

  # Creates a new MiddlewareStack. Once created, handlers can be added using `:<<`
  def initialize
    @handlers = []
  end

  # Adds a handler. The handler should respond to :around_deserialization and #around_execution.
  #
  # @param handler[#around_deserializarion, #around_execution] The middleware item to insert
  # @return [void]
  def <<(handler)
    @handlers << handler
    # TODO: cache the wrapping proc
  end

  def around_execution(job, context, &inner_block)
    return yield if @handlers.empty?

    responders = @handlers.select{|e| e.respond_to?(:around_execution) }
    responders.reverse.inject(inner_block) {|outer_block, middleware_object|
      ->{
        middleware_object.public_send(:around_execution, job, context, &outer_block)
      }
    }.call
  end

  def around_deserialization(serializer, message_id, message_body, message_attributes, &inner_block)
    return yield if @handlers.empty?

    responders = @handlers.select{|e| e.respond_to?(:around_deserialization) }
    responders.reverse.inject(inner_block) {|outer_block, middleware_object|
      ->{ middleware_object.public_send(:around_deserialization, serializer, message_id, message_body, message_attributes, &outer_block) }
    }.call
  end
end
