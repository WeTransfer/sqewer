module Sqewer
  require 'sqewer/extensions/active_job_adapter' if defined?(::ActiveJob)

  # Ensures that within the Sqewer worker process, the Rails eager loading of classes
  # is forcibly enabled (Sqewer is threaded and autoloading does not play nice with that).
  def self.force_enable_eager_loading_of_rails_classes
    # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb
    require 'rails'
    # Painful contortions, see https://github.com/mperham/sidekiq/issues/1791
    require File.expand_path('config/application.rb')
    ::Rails::Application.initializer 'sqewer.eager_load' do
      ::Rails.application.config.eager_load = true
    end
    require File.expand_path('config/environment.rb')
  end

  # Loads the Sqewer components that provide ActiveJob compatibility
  class Railtie < Rails::Railtie
    initializer "sqewer.load_active_job_adapter" do |app|
    end
  end
end
