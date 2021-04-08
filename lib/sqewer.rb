# The enclosing module for the library
module Sqewer
  class Error < StandardError
  end

  # Eager-load everything except extensions. Sort to ensure
  # the files load in the same order on all platforms.
  Dir.glob(__dir__ + '/**/*.rb').sort.each do |path|
    if path != __FILE__ && File.dirname(path) !~ /\/extensions$/
      require path
    end
  end

  # Sets an instance of Aws::SQS::Client to be used as a singleton.
  # We recommend setting the options instance_profile_credentials_timeout and
  # instance_profile_credentials_retries, for example:
  #
  #   sqs_client = Aws::SQS::Client.new(
  #     instance_profile_credentials_timeout: 1,
  #     instance_profile_credentials_retries: 5,
  #   )
  #   Storm.client = sqs_client
  #
  # @param client[Aws::SQS::Client] an instance of Aws::SQS::Client
  def self.client=(client)
    @client = client
  end

  def self.client
    @client
  end

  # Loads a particular Sqewer extension that is not loaded
  # automatically during the gem require.
  #
  # @param extension_name[String] the name of the extension to load (like `active_job_adapter`)
  def self.require_extension(extension_name)
    path = File.join("sqewer", "extensions", extension_name)
    require_relative path
  end

  # Shortcut access to Submitter#submit.
  #
  # @see {Sqewer::Submitter#submit!}
  def self.submit!(*jobs, **options)
    Sqewer::Submitter.default.submit!(*jobs, **options)
  end

  # If we are within Rails, load the railtie
  require_relative 'sqewer/extensions/railtie' if defined?(Rails)

  # Explicitly require retriable so that it ia available for use.
  require 'retriable'
end
