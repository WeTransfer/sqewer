module Sqewer
  require 'sqewer/extensions/active_job_adapter' if defined?(::ActiveJob)
  
  # Loads the Sqewer components that provide ActiveJob compatibility
  class Railtie < Rails::Railtie
    initializer "sqewer.load_active_job_adapter" do |app|
      if defined?(::ActiveJob)
        Rails.logger.warn "sqewer set as ActiveJob adapter. Make sure to call 'Rails.application.eager_load!` in your worker process"
      end
    end
  end
end
