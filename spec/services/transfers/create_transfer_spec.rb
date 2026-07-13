require "rails_helper"

RSpec.describe Transfers::CreateTransfer, type: :service do
  let(:user) { create(:user) }
  let(:from) { create(:account, user:, name: "Checking", initial_balance: 1000) }
  let(:to)   { create(:account, user:, name: "Savings", initial_balance: 0) }

  let(:valid_params) do
    { from_account_id: from.id, to_account_id: to.id, amount: 250, date: Date.current,
      description: "Move to savings" }
  end

  it "creates two linked legs sharing a transfer_id" do
    result = nil
    expect { result = described_class.call(user:, params: valid_params) }
      .to change(user.transactions, :count).by(2)
    expect(result).to be_success

    legs = user.transactions.where(transfer_id: result.data[:transfer_id])
    expect(legs.pluck(:kind, :account_id)).to contain_exactly(
      ["expense", from.id], ["income", to.id]
    )
    expect(legs.map(&:transfer?)).to all(be true)
  end

  it "moves money between the two account balances" do
    described_class.call(user:, params: valid_params)
    calc = Accounts::BalanceCalculator.new(user:)
    expect(calc.account_balance(from)).to eq(750)
    expect(calc.account_balance(to)).to eq(250)
  end

  it "does not require a category on either leg" do
    described_class.call(user:, params: valid_params)
    expect(user.transactions.where(category_id: nil).count).to eq(2)
  end

  it "fails when source and destination are the same" do
    result = described_class.call(user:, params: valid_params.merge(to_account_id: from.id))
    expect(result).to be_failure
  end

  it "fails when the source account does not exist" do
    result = described_class.call(user:, params: valid_params.merge(from_account_id: 0))
    expect(result).to be_failure
    expect(result.errors).to include("Source account not found")
  end

  it "fails when an account does not belong to the user" do
    stranger = create(:account)
    result = described_class.call(user:, params: valid_params.merge(to_account_id: stranger.id))
    expect(result).to be_failure
  end

  it "writes nothing when a leg is invalid" do
    expect { described_class.call(user:, params: valid_params.merge(amount: -5)) }
      .not_to change(Transaction, :count)
  end
end
