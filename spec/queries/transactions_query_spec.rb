require "rails_helper"

RSpec.describe TransactionsQuery do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:other_account) { create(:account, user:, name: "Other") }
  let(:expense_cat) { create(:category, user:, kind: "expense") }
  let(:income_cat) { create(:income_category, user:) }

  let!(:groceries) do
    create(:transaction, user:, account:, category: expense_cat,
                         description: "Groceries", amount: 50, date: Date.new(2026, 5, 10), paid: true)
  end
  let!(:salary) do
    create(:income_transaction, user:, account:, category: income_cat,
                                description: "Salary", amount: 3000, date: Date.new(2026, 5, 1), paid: true)
  end
  let!(:rent) do
    create(:transaction, user:, account: other_account, category: expense_cat,
                         description: "Rent", amount: 900, date: Date.new(2026, 4, 20), paid: false)
  end

  def run(params)
    described_class.new(user.transactions, params).call
  end

  it "returns all transactions ordered by date desc by default" do
    expect(run({}).to_a).to eq([groceries, salary, rent])
  end

  it "filters by kind" do
    expect(run(kind: "income")).to contain_exactly(salary)
  end

  it "filters by account" do
    expect(run(account_id: other_account.id)).to contain_exactly(rent)
  end

  it "filters by credit card" do
    card = create(:credit_card, user:)
    card_tx = create(:transaction, user:, account: nil, credit_card: card,
                                   category: expense_cat, paid: false)
    expect(run(credit_card_id: card.id)).to contain_exactly(card_tx)
  end

  it "filters by category" do
    expect(run(category_id: income_cat.id)).to contain_exactly(salary)
  end

  it "filters by paid flag" do
    expect(run(paid: "false")).to contain_exactly(rent)
  end

  it "filters by a date range" do
    expect(run(from: "2026-05-01", to: "2026-05-31")).to contain_exactly(groceries, salary)
  end

  it "ignores an invalid date range" do
    expect(run(from: "garbage", to: "also-bad").count).to eq(3)
  end

  it "searches the description (case-insensitive)" do
    expect(run(search: "grocer")).to contain_exactly(groceries)
  end

  it "sorts by an allowed column and direction" do
    expect(run(sort: "amount", direction: "asc").first).to eq(groceries)
  end

  it "falls back to date for a disallowed sort column" do
    expect(run(sort: "amount; DROP TABLE", direction: "asc").to_a).to eq([rent, salary, groceries])
  end
end
