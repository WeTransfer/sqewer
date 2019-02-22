source "http://rubygems.org"
gem 'activerecord', "~> 4"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem 'rake', '~> 10.0'
  gem 'sqlite3'
  gem "rspec", "~> 2.4"
  gem "rdoc", "~> 3.12"
  gem "bundler", "~> 1.0"
end
