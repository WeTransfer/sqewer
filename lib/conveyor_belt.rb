module ConveyorBelt
  Dir.glob(__dir__ + '/**/*.rb').each {|p| require p unless p == __FILE__ }
end
