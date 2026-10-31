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
                                         { category_id: rent.id, name: rent.name, color: rent.color, icon: nil,
                                           total: 800, children: [] },
                                         { category_id: food.id, name: food.name, color: food.color, icon: nil,
                                           total: 200, children: [] }
                                       ])
  end

  # Card charges count in the month their invoice is due, paid or not, so the
  # month's spending does not move when the bill gets paid.
  describe "card charges" do
    let(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1) }

    def charge(amount, date, paid: false, kind: "expense", invoice_month: nil)
      category = kind == "expense" ? food : income_cat
      create(:transaction, user:, category:, account: nil, credit_card: card, kind:, amount:, date:, paid:,
                           invoice_month:)
    end

    before do
      charge(120, Date.new(2026, 4, 10))                    # invoice due May, still pending
      charge(30, Date.new(2026, 4, 12), paid: true)         # invoice due May, already paid
      charge(15, Date.new(2026, 4, 15), kind: "income")     # credit on the May invoice
      charge(70, Date.new(2026, 5, 10))                     # invoice due June
      charge(55, Date.new(2026, 4, 1), invoice_month: Date.new(2026, 6, 1)) # pushed to June
    end

    it "counts every charge on the invoice due this month in the totals, paid or not" do
      expect(result[:totals]).to eq(income: 5015, expense: 350, net: 4665)
    end

    it "keeps them out of the forecast, which is account entries still scheduled" do
      expect(result[:forecast]).to eq(income: 0, expense: 800)
    end

    # Unlike the totals, the breakdown goes by purchase date, as Organizze's
    # "Maiores gastos" chart does: the 200 on the account and the 70 bought in May.
    it "breaks them down by category in the month they were bought" do
      expect(result[:by_category].find { |row| row[:category_id] == food.id }[:total]).to eq(270)
    end

    it "counts an installment purchase once, by its first parcel" do
      series_id = SecureRandom.uuid
      [[1, Date.new(2026, 5, 3)], [2, Date.new(2026, 6, 3)]].each do |number, date|
        create(:transaction, user:, category: food, account: nil, credit_card: card, amount: 100, date:,
                             series_id:, installment_number: number, installment_total: 2)
      end
      june = described_class.new(user, month: Date.new(2026, 6, 1)).call

      expect(result[:by_category].find { |row| row[:category_id] == food.id }[:total]).to eq(370)
      expect(june[:by_category].find { |row| row[:category_id] == food.id }).to be_nil
    end
  end

  it "leaves entries on an account in another currency out of the totals" do
    usd = create(:account, user:, currency: "USD")
    create(:transaction, user:, account: usd, category: food, amount: 75, date: Date.new(2026, 5, 7))

    expect(result[:totals][:expense]).to eq(200)
    expect(result[:by_category].pluck(:total).sum).to eq(1000)
  end

  it "defaults to the current month when none is given" do
    res = described_class.new(user).call
    expect(res[:period][:from]).to eq(Date.current.beginning_of_month)
  end
end
