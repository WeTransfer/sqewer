# This module enables the acceptance of kwargs for the perform method inside
# of ActiveJob::Execution (only needed on ActiveJob versions < 5)
module PerformWithKeywords
  def perform_now
    deserialize_arguments_if_needed
    run_callbacks :perform do
      args_with_symbolized_options = arguments.map do |a|
        a.respond_to?(:symbolize_keys) ? a.symbolize_keys : a
      end
      perform(*args_with_symbolized_options)
    end
  rescue => exception
    rescue_with_handler(exception) || raise(exception)
  end
end
