require_relative "boot"

require "rails"
# Pick only the frameworks we need (API-only).
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile.
Bundler.require(*Rails.groups)

module Rialign
  class Application < Rails::Application
    config.load_defaults 8.0

    # API-only application: no cookies, sessions, flash, asset pipeline.
    config.api_only = true

    # Autoload lib/ (e.g. JsonWebToken) but skip non-ruby asset/task dirs.
    config.autoload_lib(ignore: %w[assets tasks])

    # All routes live under /api, so keep timezone in UTC for consistency.
    config.time_zone = "UTC"

    # Use Sidekiq-friendly default; inline for now (no background infra yet).
    config.active_job.queue_adapter = :async
  end
end
