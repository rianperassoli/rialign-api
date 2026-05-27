FactoryBot.define do
  factory :account do
    user
    name { "Checking" }
    account_type { "checking" }
    initial_balance { 1000 }
  end
end
