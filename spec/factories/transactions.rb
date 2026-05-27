FactoryBot.define do
  factory :transaction do
    user
    description { "Groceries" }
    kind { "expense" }
    amount { 100 }
    date { Date.current }
    paid { true }
    account { association :account, user: user }
    category { association :category, user: user, kind: kind }

    factory :income_transaction do
      kind { "income" }
      description { "Salary" }
      amount { 3000 }
      category { association :income_category, user: user }
    end
  end
end
