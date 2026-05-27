require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "shoulda/matchers"
require "database_cleaner/active_record"

# Load support files (helpers, shared examples).
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

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

  # Request spec auth helper.
  config.include AuthHelpers, type: :request

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
