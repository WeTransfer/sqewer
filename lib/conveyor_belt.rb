# The enclosing module for the library
module ConveyorBelt
  Dir.glob(__dir__ + '/**/*.rb').each {|p| require p unless p == __FILE__ }
  
  # Shortcut access to Submitter#submit.
  #
  # @see {ConveyorBelt::Submitter#submit!}
  def self.submit!(*jobs, **options)
    ConveyorBelt::Submitter.default.submit!(*jobs, **options)
  end
end
