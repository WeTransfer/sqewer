source "http://rubygems.org"

# Gemspec as base dependency set
gemspec path: __dir__ + '/..'

gem 'sqlite3', "~> 1.3", ">= 1.3.6"
gem 'activejob', "~> 7.0.0"
gem 'activerecord', "~> 7.0.0"
