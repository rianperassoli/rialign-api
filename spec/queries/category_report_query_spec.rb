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

  describe "filters" do
    let(:market) { create(:category, user:, name: "Mercado", parent: shopping) }
    let(:rent) { create(:category, user:, name: "Aluguel") }

    def filtered(**filters)
      described_class.new(user, period: october, filters:).call[:expense].to_h { |row| [row[:name], row[:total].to_f] }
    end

    before do
      create(:transaction, user:, account:, category: market, amount: 25, date: Date.new(2026, 10, 3))
      create(:transaction, user:, account:, category: rent, amount: 900, date: Date.new(2026, 10, 6), paid: false)
    end

    it "counts settled and pending entries alike unless a status is picked" do
      expect(filtered).to eq("Aluguel" => 900, "Compras" => 65)
      expect(filtered(status: "paid")).to eq("Compras" => 25)
      expect(filtered(status: "unpaid")).to eq("Aluguel" => 900, "Compras" => 40)
      expect(filtered(status: "maybe")).to eq("Aluguel" => 900, "Compras" => 65)
    end

    it "keeps the categories picked, a parent with its subcategories" do
      expect(filtered(category_ids: [shopping.id])).to eq("Compras" => 65)
      expect(filtered(category_ids: [market.id, rent.id])).to eq("Aluguel" => 900, "Compras" => 25)
    end

    it "keeps the entries on the accounts and cards picked" do
      expect(filtered(account_ids: [account.id])).to eq("Aluguel" => 900, "Compras" => 25)
      expect(filtered(credit_card_ids: [card.id])).to eq("Compras" => 40)
    end
  end
end
