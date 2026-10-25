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

  it "links every charge it settles to the payment" do
    charge = add_card_expense(200)
    settlement = described_class.call(user:, credit_card: card).data[:transaction]

    expect(charge.reload.settled_by).to eq(settlement)
    expect(settlement.settled_charges).to contain_exactly(charge)
  end

  it "reopens only its own charges when the payment is removed, even archived ones" do
    earlier = add_card_expense(80, paid: true)
    charge = add_card_expense(200)
    archived = add_card_expense(10)
    settlement = described_class.call(user:, credit_card: card).data[:transaction]
    archived.reload.archive!

    settlement.destroy

    expect(charge.reload).to have_attributes(paid: false, settled_by_id: nil)
    expect(Transaction.unscoped.find(archived.id).settled_by_id).to be_nil
    expect(earlier.reload.paid).to be(true)
    expect(settlement.reload).to be_archived
  end

  it "does nothing more when an already removed payment is removed again" do
    add_card_expense(200)
    settlement = described_class.call(user:, credit_card: card).data[:transaction]
    settlement.destroy
    reopened = card.transactions.sole
    reopened.update!(paid: true)

    settlement.destroy
    expect(reopened.reload.paid).to be(true)
  end

  describe "partial payment" do
    let(:month) { card.current_invoice_month }

    def pay(amount, **extra)
      described_class.call(user:, credit_card: card, params: { month: month.strftime("%Y-%m"), amount:, **extra })
    end

    it "settles the invoice and moves the rest to the next one as a remaining balance" do
      add_card_expense(300)
      result = pay("120.50")

      expect(result.data).to include(amount: 120.50, remaining: 179.50)
      expect(CreditCardInvoiceQuery.new(card, month:).call[:status]).to eq("paid")
      remainder = card.transactions.pending.sole
      expect(remainder).to have_attributes(amount: 179.50, invoice_month: month >> 1,
                                           transfer_id: result.data[:transaction].transfer_id)
      expect(card.reload.available_limit).to eq(card.credit_limit - 179.50)
    end

    it "takes only what was paid from the account and keeps the remainder out of reports" do
      add_card_expense(300)
      pay(100)

      expect(Accounts::BalanceCalculator.new(user:).account_balance(account)).to eq(900)
      expect(DashboardQuery.new(user, month: month >> 1).call[:totals][:expense]).to eq(0)
    end

    it "removes the remaining balance and reopens the invoice when undone" do
      add_card_expense(300)
      payment = pay(100).data[:transaction]
      user.transactions.where(transfer_id: payment.transfer_id).find_each(&:destroy)

      expect(card.transactions.pending.sole.amount).to eq(300)
    end

    it "cannot be undone once a later payment settled the remaining balance" do
      add_card_expense(300)
      first = pay(100).data[:transaction]
      described_class.call(user:, credit_card: card, params: { month: (month >> 1).strftime("%Y-%m") })

      expect { first.destroy }.to raise_error(ActiveRecord::RecordNotDestroyed, /undo that payment first/)
      remainder = card.transactions.find_by(transfer_id: first.transfer_id)
      expect { remainder.destroy }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end

    it "rejects an amount that is zero, unreadable or above the total" do
      add_card_expense(300)

      expect(pay(0).errors).to include("Amount must be greater than zero")
      expect(pay("abc").errors).to include("Amount must be greater than zero")
      expect(pay(301).errors).to include("Amount cannot exceed the invoice total")
      expect(card.transactions.pending.count).to eq(1)
    end

    it "needs the invoice month to know where the rest goes" do
      add_card_expense(300)
      result = described_class.call(user:, credit_card: card, params: { amount: 100 })
      expect(result.errors).to include("A partial payment needs the invoice month")
    end

    it "is a full payment when the amount is the whole total" do
      add_card_expense(300)
      expect(pay(300).data[:remaining]).to eq(0)
      expect(card.transactions.pending).to be_empty
    end
  end

  it "marks the card's pending expenses as paid" do
    add_card_expense(200)
    described_class.call(user:, credit_card: card)
    expect(card.transactions.expense.pending.count).to eq(0)
  end

  it "lowers the account balance without inflating reported expense" do
    charge = add_card_expense(200)
    described_class.call(user:, credit_card: card)

    expect(Accounts::BalanceCalculator.new(user:).account_balance(account)).to eq(800)

    # The card expense counts once, in its invoice month; the settlement leg
    # (paid today, on the account) is excluded.
    dashboard = DashboardQuery.new(user, month: charge.invoice_month).call
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
