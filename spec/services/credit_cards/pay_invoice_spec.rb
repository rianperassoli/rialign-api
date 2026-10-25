require "rails_helper"

RSpec.describe CreditCards::PayInvoice, type: :service do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:, initial_balance: 1000) }
  let(:card) { create(:credit_card, user:, payment_account: account) }

  def add_card_expense(amount, paid: false)
    create(:transaction, user:, credit_card: card, account: nil, kind: "expense",
                         amount:, paid:)
  end

  it "settles the open invoice from the payment account" do
    add_card_expense(200)
    add_card_expense(150)

    result = described_class.call(user:, credit_card: card)
    expect(result).to be_success
    expect(result.data[:amount]).to eq(350)

    settlement = result.data[:transaction]
    expect(settlement.account_id).to eq(account.id)
    expect(settlement.kind).to eq("expense")
    expect(settlement.transfer?).to be true
  end

  def add_card_credit(amount)
    create(:transaction, user:, credit_card: card, account: nil, kind: "income", amount:, paid: false,
                         category: create(:income_category, user:))
  end

  it "pays charges net of credits and settles the credits with them" do
    add_card_expense(200)
    credit = add_card_credit(50)

    result = described_class.call(user:, credit_card: card)
    expect(result.data[:amount]).to eq(150)
    expect(credit.reload.paid).to be(true)
  end

  it "has nothing to pay while credits outweigh the charges, leaving them to carry over" do
    add_card_expense(20)
    credit = add_card_credit(50)

    result = described_class.call(user:, credit_card: card)
    expect(result).to be_failure
    expect(credit.reload.paid).to be(false)
  end

  it "marks the card's pending expenses as paid" do
    add_card_expense(200)
    described_class.call(user:, credit_card: card)
    expect(card.transactions.expense.pending.count).to eq(0)
  end

  it "lowers the account balance without inflating reported expense" do
    add_card_expense(200)
    described_class.call(user:, credit_card: card)

    expect(Accounts::BalanceCalculator.new(user:).account_balance(account)).to eq(800)

    dashboard = DashboardQuery.new(user).call
    # The card expense counts once; the settlement leg is excluded.
    expect(dashboard[:totals][:expense]).to eq(200)
  end

  it "fails when there is no open invoice" do
    result = described_class.call(user:, credit_card: card)
    expect(result).to be_failure
  end

  it "fails when no payment account is set and none is given" do
    card.update!(payment_account: nil)
    add_card_expense(200)
    result = described_class.call(user:, credit_card: card)
    expect(result).to be_failure
  end

  it "returns a failure (and writes nothing) when the settlement is invalid" do
    add_card_expense(200)
    expect do
      result = described_class.call(user:, credit_card: card, params: { date: "not-a-date" })
      expect(result).to be_failure
    end.not_to change(user.transactions.non_transfer, :count)
    # the rolled-back update_all left the invoice untouched
    expect(card.transactions.expense.pending.count).to eq(1)
  end

  it "accepts an explicit account override" do
    other = create(:account, user:, name: "Other")
    add_card_expense(200)
    result = described_class.call(user:, credit_card: card, params: { account_id: other.id })
    expect(result.data[:transaction].account_id).to eq(other.id)
  end
end
