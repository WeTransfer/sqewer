require 'logger'

module Sqewer::NullLogger
  (Logger.instance_methods- Object.instance_methods).each do | null_method |
    define_method(null_method){|*a| }
  end

  extend self
end
