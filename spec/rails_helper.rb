require "spec_helper"
# Hard-assign (not ||=): the Docker container exports RAILS_ENV=development,
# which would silently run the suite — and DatabaseCleaner — against the dev DB.
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

abort("The Rails environment is running in #{Rails.env} mode!") unless Rails.env.test?

require "rspec/rails"
require "shoulda/matchers"
require "database_cleaner/active_record"

# Load support files (helpers, shared examples).
Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

# Fail fast on pending migrations.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot DSL: build(:user) instead of FactoryBot.build(:user).
  config.include FactoryBot::Syntax::Methods
  # Lets specs pin Date.current where behaviour depends on today's position in
  # a billing cycle (see CreditCard#open_invoice).
  config.include ActiveSupport::Testing::TimeHelpers

  # Request spec auth helper.
  config.include AuthHelpers, type: :request

  # rspec-rails populates config.hosts with .localhost/.test patterns, so the
  # default integration host "www.example.com" trips Host Authorization (403).
  # Use a host that matches the permitted ".test" suffix instead.
  config.before(:each, type: :request) { host! "example.test" }

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
