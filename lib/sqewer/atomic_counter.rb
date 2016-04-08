require 'thread'

# Maintains a thread-safe counter wrapped in a Mutex.
class Sqewer::AtomicCounter
  def initialize
    @m, @v = Mutex.new, 0
  end

  # Returns the current value of the counter
  #
  # @return [Fixnum] the current value of the counter
  def to_i
    @m.synchronize { @v + 0 }
  end

  # Increments the counter
  #
  # @return [Fixnum] the current value of the counter
  def increment!
    @m.synchronize { @v += 1 }
  end
end
