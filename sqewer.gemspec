# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sqewer/version"

Gem::Specification.new do |spec|
  spec.name          = "sqewer"
  spec.version       = Sqewer::VERSION
  spec.authors       = ["Julik Tarkhanov", "Andrei Horak"]
  spec.email         = ["me@julik.nl", "linkyndy@gmail.com"]

  spec.summary       = %q{Process jobs from SQS}
  spec.description   = %q{A full-featured library for all them SQS worker needs}
  spec.homepage      = "https://github.com/WeTransfer/sqewer"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "aws-sdk-sqs", "~> 1"
  spec.add_runtime_dependency "rack"
  spec.add_runtime_dependency "very_tiny_state_machine"
  spec.add_runtime_dependency "ks"
  spec.add_runtime_dependency "retriable"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  # The Rails deps can be relaxed, they are specified more exactly in the gemfiles/
  # for testing against a specific Rails version
  spec.add_development_dependency "activerecord", ">= 4.2"
  spec.add_development_dependency "activejob", ">= 4.2"

  spec.add_development_dependency "rspec-wait"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "dotenv"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "appsignal", '~> 3'
  spec.add_development_dependency "pry-byebug"
end
