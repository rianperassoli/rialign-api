require "rails_helper"

RSpec.describe Transfers::UpdateTransfer, type: :service do
  let(:user) { create(:user) }
  let(:from) { create(:account, user:, name: "Checking", initial_balance: 0) }
  let(:to) { create(:account, user:, name: "Savings", initial_balance: 0) }
  let(:other) { create(:account, user:, name: "Wallet", initial_balance: 0) }
  let(:legs) do
    id = Transfers::CreateTransfer.call(user:, params: { from_account_id: from.id, to_account_id: to.id,
                                                         amount: 100, date: Date.new(2026, 5, 1) }).data[:transfer_id]
    user.transactions.where(transfer_id: id).order(:id).to_a
  end

  def update(on: legs, **params)
    described_class.call(user:, legs: on, params:)
  end

  def balance(account)
    Accounts::BalanceCalculator.new(user:).account_balance(account)
  end

  it "changes amount, date and description on both legs together" do
    result = update(amount: 250, date: "2026-05-03", description: "Reserva")

    expect(result).to be_success
    expect(legs.map(&:reload)).to all(have_attributes(amount: 250, date: Date.new(2026, 5, 3), description: "Reserva"))
    expect([balance(from), balance(to)]).to eq([-250, 250])
  end

  it "moves the source and destination to other accounts" do
    update(from_account_id: other.id)

    expect([balance(from), balance(other), balance(to)]).to eq([0, -100, 100])
  end

  it "refuses to leave both sides on the same account" do
    expect(update(to_account_id: from.id).errors).to include("Source and destination must differ")
    expect(legs.map { |leg| leg.reload.account_id }).to eq([from.id, to.id])
  end

  it "refuses an account that is not the user's" do
    expect(update(to_account_id: create(:account).id).errors).to include("Account not found")
  end

  it "reports a leg that cannot be saved" do
    expect(update(amount: 0)).to be_failure
  end

  it "edits a single unpaired leg, as an import leaves them" do
    leg = user.transactions.create!(account: from, kind: "expense", amount: 40, date: Date.current,
                                    description: "Pix", transfer_id: SecureRandom.uuid)

    expect(update(amount: 45, to_account_id: to.id, on: [leg])).to be_success
    expect(leg.reload).to have_attributes(amount: 45, account_id: from.id)
  end

  it "refuses to edit an invoice payment, which is undone from the invoice instead" do
    card = create(:credit_card, user:, payment_account: from)
    create(:transaction, user:, credit_card: card, account: nil, amount: 80, paid: false)
    payment = CreditCards::PayInvoice.call(user:, credit_card: card,
                                           params: { month: card.current_invoice_month.strftime("%Y-%m") })
                                     .data[:transaction]

    expect(update(amount: 10, on: [payment])).to be_failure
    expect(payment.reload.amount).to eq(80)
  end

  describe "between currencies" do
    let(:usd) { create(:account, user:, name: "Global", currency: "USD", initial_balance: 0) }
    let(:legs) do
      id = Transfers::CreateTransfer.call(user:, params: { from_account_id: from.id, to_account_id: usd.id,
                                                           amount: 550, received_amount: 100,
                                                           date: Date.new(2026, 5, 1) }).data[:transfer_id]
      user.transactions.where(transfer_id: id).order(:id).to_a
    end

    it "keeps what arrived when only the amount sent changes" do
      update(amount: 600)
      expect([balance(from), balance(usd)]).to eq([-600, 100])
    end

    it "takes a new amount received for the destination" do
      update(received_amount: 110)
      expect([balance(from), balance(usd)]).to eq([-550, 110])
    end
  end
end
