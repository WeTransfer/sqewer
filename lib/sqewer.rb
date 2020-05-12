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
