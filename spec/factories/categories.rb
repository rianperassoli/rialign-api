FactoryBot.define do
  factory :category do
    user
    name { "Food" }
    kind { "expense" }
    color { "#e67e22" }

    factory :income_category do
      name { "Salary" }
      kind { "income" }
    end
  end
end
