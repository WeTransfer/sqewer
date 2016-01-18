module Sqewer
  module Contrib
    # A job class that can be used to adapt Jobs from ActiveJob and friends. They use
    # the `perform` method which gets the arguments.
    class Performable
      def initialize(performable_class:, perform_arguments:)
        @class, @args = performable_class, perform_arguments
      end
      
      def to_h
        {performable_class: @class, perform_arguments: @args}
      end
      
      def inspect
        '<%s{%s}>' % [@class, @args.inspect]
      end
      
      def run(context)
        Kernel.const_get(@class).perform(*@args)
      end
    end
  end
end
