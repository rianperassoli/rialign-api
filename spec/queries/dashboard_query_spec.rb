require "rails_helper"

RSpec.describe DashboardQuery do
  subject(:result) { described_class.new(user, month:).call }

  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:food) { create(:category, user:, kind: "expense", name: "Food") }
  let(:rent) { create(:category, user:, kind: "expense", name: "Rent") }
  let(:income_cat) { create(:income_category, user:) }
  let(:month) { Date.new(2026, 5, 1) }

  before do
    create(:income_transaction, user:, account:, category: income_cat, amount: 5000, date: Date.new(2026, 5, 2),
                                paid: true)
    create(:transaction, user:, account:, category: food, amount: 200, date: Date.new(2026, 5, 5), paid: true)
    create(:transaction, user:, account:, category: rent, amount: 800, date: Date.new(2026, 5, 6), paid: false)
    # outside the month, must be excluded
    create(:transaction, user:, account:, category: food, amount: 999, date: Date.new(2026, 4, 30), paid: true)
  end

  it "reports the period boundaries" do
    expect(result[:period]).to eq(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 31))
  end

  it "totals paid income/expense and net for the month" do
    expect(result[:totals]).to eq(income: 5000, expense: 200, net: 4800)
  end

  it "reports pending amounts as forecast" do
    expect(result[:forecast]).to eq(income: 0, expense: 800)
  end

  it "groups expenses by category (paid + pending) with name/color, biggest first" do
    expect(result[:by_category]).to eq([
                                         { category_id: rent.id, name: rent.name, color: rent.color, total: 800 },
                                         { category_id: food.id, name: food.name, color: food.color, total: 200 }
                                       ])
  end

  it "defaults to the current month when none is given" do
    res = described_class.new(user).call
    expect(res[:period][:from]).to eq(Date.current.beginning_of_month)
  end
end
