# SimpleCov must start before any application code is loaded.
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter %w[/spec/ /config/ /bin/ /db/]

  add_group "Services", "app/services"
  add_group "Queries", "app/queries"
  add_group "Serializers", "app/serializers"
  add_group "Policies", "app/policies"

  # Enforce full coverage as a hard gate.
  minimum_coverage line: 100, branch: 100
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
