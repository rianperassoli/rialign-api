require "rails_helper"

RSpec.describe InvoiceAdjustment do
  let(:user) { create(:user) }
  let(:card) { create(:credit_card, user:, closing_day: 31, due_day: 10) }
  let(:october) { Date.new(2026, 10, 1) }

  def settled(amount, month, kind: "expense")
    category = create(:category, user:, kind:)
    create(:transaction, user:, account: nil, credit_card: card, category:, kind:, amount:, paid: true,
                         date: month << 1, invoice_month: month)
  end

  def adjustments
    user.transactions.transfers.where(credit_card: card)
  end

  it "takes a raised refund off the next invoice, as a credit" do
    refund = settled(30, october, kind: "income")
    refund.update!(amount: 50)

    expect(adjustments.sole).to have_attributes(kind: "income", amount: 20, invoice_month: october >> 1)
  end

  it "skips invoices already paid, landing on the first one still open" do
    charge = settled(100, october)
    settled(40, october >> 1)

    charge.update!(amount: 120)
    expect(adjustments.sole).to have_attributes(kind: "expense", amount: 20, invoice_month: october >> 2)
  end

  it "leaves pending charges and account entries alone" do
    pending = create(:transaction, user:, account: nil, credit_card: card, paid: false, date: october)
    pending.update!(amount: 999)
    pending.archive!
    create(:transaction, user:, paid: true).update!(amount: 999)

    expect(user.transactions.transfers).to be_empty
  end
end
