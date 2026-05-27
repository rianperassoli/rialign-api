source "https://rubygems.org"

ruby "3.3.0"

gem "pg", "~> 1.5"
gem "puma", "~> 6.4"
gem "rails", "~> 8.0.0"

# Auth
gem "bcrypt", "~> 3.1.7"
gem "jwt", "~> 2.8"

# API helpers
gem "pagy", "~> 9.0"          # pagination
gem "rack-cors"               # CORS

# Boot performance
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails", "~> 7.0"
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
end

group :test do
  gem "database_cleaner-active_record"
  gem "shoulda-matchers", "~> 6.0"
  gem "simplecov", require: false
end
