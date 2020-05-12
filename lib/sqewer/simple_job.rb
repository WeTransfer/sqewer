# A module that you can include into your Job class.
# It adds the following features:
#
# * initialize() will have keyword access to all accessors, and will ensure you have called each one of them
# * to_h() will produce a symbolized Hash with all the properties defined using attr_accessor, and the job_class_name
# * inspect() will provide a sensible default string representation for logging
module Sqewer::SimpleJob
  UnknownJobAttribute = Class.new(Sqewer::Error)
  MissingAttribute = Class.new(Sqewer::Error)

  EQ_END = /(\w+)(\=)$/

  # Returns the list of methods on the object that have corresponding accessors.
  # This is then used by #inspect to compose a list of the job parameters, formatted
  # as an inspected Hash.
  #
  # @return [Array<Symbol>] the array of attributes to show via inspect
  def inspectable_attributes
    # All the attributes that have accessors
    methods.grep(EQ_END).map{|e| e.to_s.gsub(EQ_END, '\1')}.map(&:to_sym)
  end

  # Returns the inspection string with the job and all of it's instantiation keyword attributes.
  # If `inspectable_attributes` has been overridden, the attributes returned by that method will be the
  # ones returned in the inspection string.
  #
  #     j = SomeJob.new(retries: 4, param: 'a')
  #     j.inspect #=> "<SomeJob:{retries: 4, param: \"a\"}>"
  #
  # @return [String] the object inspect string
  def inspect
    key_attrs = inspectable_attributes
    hash_repr = to_h
    h = key_attrs.each_with_object({}) do |k, o|
      o[k] = hash_repr[k]
    end
    "<#{self.class}:#{h.inspect}>"
  end

  # Initializes a new Job with the given job args. Will check for presence of
  # accessor methods for each of the arguments, and call them with the arguments given.
  #
  # If one of the accessors was not triggered during the call, an exception will be raised
  # (because you most likely forgot a parameter for a job, or the job class changed whereas
  # the queue still contains jobs in old formats).
  #
  # @param jobargs[Hash] the keyword arguments, mapping 1 to 1 to the accessors of the job
  def initialize(**jobargs)
    @simple_job_args = jobargs.keys
    touched_attributes = Set.new
    jobargs.each do |(k,v)|

      accessor = "#{k}="
      touched_attributes << k
      unless respond_to?(accessor)
        raise UnknownJobAttribute, "Unknown attribute #{k.inspect} for #{self.class}" 
      end

      send("#{k}=", v)
    end

    accessors = methods.grep(EQ_END).map{|method_name| method_name.to_s.gsub(EQ_END, '\1').to_sym }
    settable_attributes = Set.new(accessors)
    missing_attributes = settable_attributes - touched_attributes

    missing_attributes.each do | attr |
      raise MissingAttribute, "Missing job attribute #{attr.inspect}"
    end
  end

  def to_h
    keys_and_values = @simple_job_args.each_with_object({}) do |k, h|
      h[k] = send(k)
    end

    keys_and_values
  end
end
