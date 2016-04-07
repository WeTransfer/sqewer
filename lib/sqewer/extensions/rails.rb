module Sqewer
  def self.load_rails
    # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb

    require 'rails'
    # Painful contortions, see https://github.com/mperham/sidekiq/issues/1791
    require File.expand_path('config/application.rb')
    ::Rails::Application.initializer 'sqewer.eager_load' do
      ::Rails.application.config.eager_load = true
    end
    require 'sqewer/extensions/active_job_adapter' if defined?(::ActiveJob)
    require File.expand_path('config/environment.rb')
  end
end
