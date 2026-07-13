require "rails_helper"

RSpec.describe CreditCardInvoiceQuery do
  subject(:result) { described_class.new(card, month: Date.new(2026, 5, 1)).call }

  let(:user) { create(:user) }
  let(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1) }
  let(:category) { create(:category, user:) }

  def charge(amount, date, paid: false)
    create(:transaction, user:, category:, account: nil, credit_card: card, amount:, date:, paid:)
  end

  it "spans the cycle between the previous and the current closing" do
    expect(result[:period]).to eq(from: Date.new(2026, 4, 21), to: Date.new(2026, 5, 20))
  end

  it "rolls the due date into the next month when due_day <= closing_day" do
    expect(result[:due_date]).to eq(Date.new(2026, 6, 1))
  end

  it "keeps the due date in the same month when due_day > closing_day" do
    query = described_class.new(create(:credit_card, user:, closing_day: 10, due_day: 20),
                                month: Date.new(2026, 5, 1))
    expect(query.call[:due_date]).to eq(Date.new(2026, 5, 20))
  end

  it "totals only charges inside the cycle" do
    charge(100, Date.new(2026, 4, 21))
    charge(50, Date.new(2026, 5, 20))
    charge(999, Date.new(2026, 5, 21)) # next cycle
    charge(999, Date.new(2026, 4, 20)) # previous cycle

    expect(result[:total]).to eq(150)
    expect(result[:transactions].map(&:amount)).to eq([100, 50])
  end

  it "is paid when the cycle has charges and none is pending" do
    charge(100, Date.new(2026, 5, 5), paid: true)
    expect(result[:status]).to eq("paid")
  end

  it "is closed when past the closing date with pending charges" do
    charge(100, Date.new(2026, 5, 5))
    expect(result[:status]).to eq("closed")
  end

  it "clamps the closing day on short months" do
    short = described_class.new(create(:credit_card, user:, closing_day: 31, due_day: 10),
                                month: Date.new(2026, 2, 1))
    expect(short.period[:to]).to eq(Date.new(2026, 2, 28))
  end
end
