source "http://rubygems.org"
gem 'activerecord', "~> 5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem 'rake', '~> 10.0'
  gem 'sqlite3'
  gem "rspec", "~> 3"
  gem "bundler"
end
