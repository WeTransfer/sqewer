module Sqewer
  # Loads the Sqewer components that provide ActiveJob compatibility
  class Railtie < Rails::Railtie
    initializer "sqewer.load_active_job_adapter" do |app|
      require 'sqewer/extensions/active_job_adapter' if defined?(::ActiveJob)
    end
  end
end
