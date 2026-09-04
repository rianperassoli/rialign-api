require "rails_helper"

RSpec.describe CreditCardInvoiceQuery do
  # Invoices are named after the month they are DUE. This card closes on the
  # 20th and is due on the 1st, so the invoice due in May 2026 is the cycle that
  # closed in April: 21/03 to 20/04.
  subject(:result) { described_class.new(card, month: Date.new(2026, 5, 1)).call }

  let(:user) { create(:user) }
  let(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1) }
  let(:category) { create(:category, user:) }

  def charge(amount, date, paid: false)
    create(:transaction, user:, category:, account: nil, credit_card: card, amount:, date:, paid:)
  end

  it "spans the cycle that closes before the due date" do
    expect(result[:period]).to eq(from: Date.new(2026, 3, 21), to: Date.new(2026, 4, 20))
  end

  it "is due on the due day of the month it is named after" do
    expect(result[:due_date]).to eq(Date.new(2026, 5, 1))
  end

  it "closes in the same month when the card is due after it closes" do
    query = described_class.new(create(:credit_card, user:, closing_day: 10, due_day: 20),
                                month: Date.new(2026, 5, 1))
    expect(query.call).to include(period: { from: Date.new(2026, 4, 11), to: Date.new(2026, 5, 10) },
                                  due_date: Date.new(2026, 5, 20))
  end

  it "totals only charges inside the cycle" do
    charge(100, Date.new(2026, 3, 21))
    charge(50, Date.new(2026, 4, 20))
    charge(999, Date.new(2026, 4, 21)) # next cycle
    charge(999, Date.new(2026, 3, 20)) # previous cycle

    expect(result[:total]).to eq(150)
    expect(result[:transactions].map(&:amount)).to eq([100, 50])
  end

  it "is paid when the cycle has charges and none is pending" do
    charge(100, Date.new(2026, 4, 5), paid: true)
    expect(result[:status]).to eq("paid")
  end

  it "is closed when past the closing date with pending charges" do
    charge(100, Date.new(2026, 4, 5))
    expect(result[:status]).to eq("closed")
  end

  it "is open while the cycle is still accumulating charges" do
    travel_to Date.new(2026, 4, 10)
    charge(100, Date.new(2026, 4, 5))
    expect(result[:status]).to eq("open")
  end

  it "clamps the closing day on short months" do
    short = described_class.new(create(:credit_card, user:, closing_day: 31, due_day: 10),
                                month: Date.new(2026, 3, 1))
    expect(short.period[:to]).to eq(Date.new(2026, 2, 28))
  end
end
