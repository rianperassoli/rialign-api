# Idempotent demo data. Safe to run repeatedly (`bin/rails db:seed`).
puts "Seeding demo data..."

user = User.find_or_initialize_by(email: "demo@rianganizze.com")
if user.new_record?
  user.assign_attributes(name: "Demo User", password: "password123", password_confirmation: "password123")
  user.save!
  Categories::SeedDefaults.call(user:)
  puts "  created user demo@rianganizze.com / password123"
end

checking = user.accounts.find_or_create_by!(name: "Main Checking") do |a|
  a.account_type = "checking"
  a.initial_balance = 5_000
end

user.accounts.find_or_create_by!(name: "Cash Wallet") do |a|
  a.account_type = "cash"
  a.initial_balance = 300
end

card = user.credit_cards.find_or_create_by!(name: "Visa Platinum") do |c|
  c.credit_limit = 10_000
  c.closing_day = 20
  c.due_day = 1
end

salary   = user.categories.find_by(name: "Salary")
food     = user.categories.find_by(name: "Food")
leisure  = user.categories.find_by(name: "Leisure")

if user.transactions.none?
  user.transactions.create!(description: "Monthly salary", kind: "income", amount: 6_500,
                            date: Date.current.beginning_of_month, paid: true,
                            account: checking, category: salary)

  user.transactions.create!(description: "Groceries", kind: "expense", amount: 420.50,
                            date: Date.current - 3, paid: true,
                            account: checking, category: food)

  user.transactions.create!(description: "Cinema", kind: "expense", amount: 60,
                            date: Date.current - 1, paid: false,
                            credit_card: card, category: leisure)

  puts "  created sample transactions"
end

puts "Done."
