require "rails_helper"

RSpec.describe CategoryReportQuery do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:card) { create(:credit_card, user:, closing_day: 31, due_day: 10) }
  let(:shopping) { create(:category, user:, name: "Compras") }
  let(:salary) { create(:income_category, user:, name: "Salário") }
  let(:october) { Date.new(2026, 10, 1)..Date.new(2026, 10, 31) }

  def totals(basis = nil)
    result = described_class.new(user, period: october, **{ basis: }.compact).call
    result[:expense].to_h { |row| [row[:name], row[:total].to_f] }
  end

  before do
    create(:income_transaction, user:, account:, category: salary, amount: 5000, date: Date.new(2026, 10, 5))
    # A 3x purchase made in September: parcels due on the October, November
    # and December invoices, each dated a month apart.
    series = SecureRandom.uuid
    3.times do |i|
      create(:transaction, user:, account: nil, credit_card: card, category: shopping, amount: 100, paid: false,
                           date: Date.new(2026, 9, 15) >> i, series_id: series, installment_number: i + 1,
                           installment_total: 3)
    end
    create(:transaction, user:, account: nil, credit_card: card, category: shopping, amount: 40, paid: false,
                         date: Date.new(2026, 10, 20))
  end

  it "lists income and expenses by category, card purchases on their purchase date by default" do
    result = described_class.new(user, period: october).call

    expect(result[:basis]).to eq("purchase")
    expect(result[:income].sole).to include(name: "Salário", total: 5000)
    expect(totals).to eq("Compras" => 40)
  end

  it "can place card charges on their invoice month or each parcel on its own date" do
    expect(totals("invoice")).to eq("Compras" => 100) # the first parcel, due in October
    expect(totals("installment")).to eq("Compras" => 140) # the second parcel and the October purchase
    expect(totals("weekly")).to eq("Compras" => 40)
  end
end
