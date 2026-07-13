require "rails_helper"

RSpec.describe ReportsQuery do
  subject(:result) { described_class.new(user, months: 3, upto: Date.new(2026, 5, 15)).call }

  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:food) { create(:category, user:, kind: "expense", name: "Food") }
  let(:income_cat) { create(:income_category, user:) }

  before do
    create(:income_transaction, user:, account:, category: income_cat, amount: 3000, date: Date.new(2026, 4, 5))
    create(:transaction, user:, account:, category: food, amount: 200, date: Date.new(2026, 4, 10))
    create(:transaction, user:, account:, category: food, amount: 100, date: Date.new(2026, 5, 2))
    # pending and out-of-window rows must be excluded
    create(:transaction, user:, account:, category: food, amount: 999, date: Date.new(2026, 5, 3), paid: false)
    create(:transaction, user:, account:, category: food, amount: 999, date: Date.new(2026, 2, 1))
  end

  it "zero-fills every month in the window, oldest first" do
    expect(result[:monthly]).to eq([
                                     { month: "2026-03", income: 0, expense: 0, net: 0 },
                                     { month: "2026-04", income: 3000, expense: 200, net: 2800 },
                                     { month: "2026-05", income: 0, expense: 100, net: -100 }
                                   ])
  end

  it "sums paid expenses per category across the window" do
    expect(result[:by_category]).to eq([
                                         { category_id: food.id, name: "Food", color: food.color, total: 300 }
                                       ])
  end

  it "clamps months to the maximum window" do
    query = described_class.new(user, months: 999)
    expect(query.call[:monthly].size).to eq(described_class::MAX_MONTHS)
  end
end
