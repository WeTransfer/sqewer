# The enclosing module for the library
module Sqewer
  # Eager-load everything except extensions
  Dir.glob(__dir__ + '/**/*.rb').each do |path|
    if path != __FILE__ && File.dirname(path) !~ /\/extensions$/
      require path
    end
  end
  
  # Shortcut access to Submitter#submit.
  #
  # @see {Sqewer::Submitter#submit!}
  def self.submit!(*jobs, **options)
    Sqewer::Submitter.default.submit!(*jobs, **options)
  end
end
