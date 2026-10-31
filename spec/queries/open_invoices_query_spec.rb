require "rails_helper"

RSpec.describe OpenInvoicesQuery do
  let(:user) { create(:user) }
  let(:checking) { create(:account, user:) }
  let(:card) do
    create(:credit_card, user:, name: "NuBank - Cartão", closing_day: 31, due_day: 10, payment_account: checking)
  end
  let(:other) { create(:credit_card, user:, name: "Outro", closing_day: 31, due_day: 4) }
  let(:november) { Date.new(2026, 11, 1)..Date.new(2026, 11, 30) }

  def charge(card, amount, invoice, paid: false)
    create(:transaction, user:, account: nil, credit_card: card, amount:, paid:, date: invoice << 1,
                         invoice_month: invoice)
  end

  it "lists the invoices still to be paid that fall due in the period, by due date" do
    charge(card, 80, Date.new(2026, 11, 1))
    charge(other, 20, Date.new(2026, 11, 1))
    charge(card, 50, Date.new(2026, 12, 1)) # due in December
    charge(other, 30, Date.new(2026, 10, 1), paid: true) # already paid

    lines = described_class.new(user, period: Date.new(2026, 10, 1)..november.end).call

    expect(lines.map { |l| [l[:name], l[:due_date], l[:amount].to_f] })
      .to eq([["Outro", Date.new(2026, 11, 4), 20.0], ["NuBank - Cartão", Date.new(2026, 11, 10), 80.0]])
  end

  it "keeps the cards paid from an account" do
    charge(card, 80, Date.new(2026, 11, 1))
    charge(other, 20, Date.new(2026, 11, 1))

    expect(described_class.new(user, period: november, account_id: checking.id).call.pluck(:name))
      .to eq(["NuBank - Cartão"])
  end
end
