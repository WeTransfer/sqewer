# The enclosing module for the library
module Sqewer
  Dir.glob(__dir__ + '/**/*.rb').each {|p| require p unless p == __FILE__ }
  
  # Shortcut access to Submitter#submit.
  #
  # @see {Sqewer::Submitter#submit!}
  def self.submit!(*jobs, **options)
    Sqewer::Submitter.default.submit!(*jobs, **options)
  end
end
