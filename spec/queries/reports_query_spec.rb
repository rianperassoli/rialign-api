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
                                         { category_id: food.id, name: "Food", color: food.color, total: 300,
                                           children: [] }
                                       ])
  end

  it "places a card charge in its invoice month, paid or not" do
    card = create(:credit_card, user:, closing_day: 20, due_day: 1)
    # Bought on 25/03, after the closing: billed on the invoice due in May.
    create(:transaction, user:, category: food, account: nil, credit_card: card, amount: 40,
                         date: Date.new(2026, 3, 25), paid: false)

    expect(result[:monthly].pluck(:month, :expense)).to eq([["2026-03", 0], ["2026-04", 200], ["2026-05", 140]])
  end

  it "breaks categories down by purchase date, an installment by its first parcel" do
    card = create(:credit_card, user:, closing_day: 20, due_day: 1)
    # Bought in February, before the window, though billed in April.
    create(:transaction, user:, category: food, account: nil, credit_card: card, amount: 40,
                         date: Date.new(2026, 2, 25), paid: false)
    series_id = SecureRandom.uuid
    # Bought in February in 2 parcels: the March one is not a purchase.
    [[1, Date.new(2026, 2, 10)], [2, Date.new(2026, 3, 10)]].each do |number, date|
      create(:transaction, user:, category: food, account: nil, credit_card: card, amount: 50, date:,
                           series_id:, installment_number: number, installment_total: 2)
    end

    expect(result[:by_category].pluck(:total)).to eq([300])
    expect(result[:monthly].pluck(:month, :expense)).to eq([["2026-03", 50], ["2026-04", 290], ["2026-05", 100]])
  end

  it "clamps months to the maximum window" do
    query = described_class.new(user, months: 999)
    expect(query.call[:monthly].size).to eq(described_class::MAX_MONTHS)
  end
end
