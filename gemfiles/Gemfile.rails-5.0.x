source "http://rubygems.org"

# Gemspec as base dependency set
gemspec path: __dir__ + '/..'

gem 'sqlite3'
gem 'activejob', "~> 5"
gem 'activerecord', "~> 5"
