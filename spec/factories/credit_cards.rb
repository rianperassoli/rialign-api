FactoryBot.define do
  factory :credit_card do
    user
    name { "Visa" }
    credit_limit { 5000 }
    closing_day { 20 }
    due_day { 1 }
  end
end
