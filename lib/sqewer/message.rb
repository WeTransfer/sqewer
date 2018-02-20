require 'securerandom'
# A wrapper for the most important properties of a message, be it a
# message we received or a message we are about to send
class Sqewer::Message
  # The "id" is only valid _within_ the request, and is used when
  # an error response refers to a specific ID within a batch
  attr_reader :id
  attr_accessor :receipt_handle
  attr_accessor :body
  attr_accessor :delay_seconds

  def initialize(**attributes)
    @id = SecureRandom.uuid
    attributes.map do |(k,v)|
      public_send("#{k}=", v)
    end
  end

  def received?
    @receipt_handle ? true : false
  end

  def inspect
    @body.inspect
  end

  def has_body?
    @body && !body.empty?
  end
end