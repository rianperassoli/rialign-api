Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(Logger.new($stdout))

  config.cache_store = :memory_store

  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]

  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"
  config.assume_ssl = true

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
end
