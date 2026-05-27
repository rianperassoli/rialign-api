require "rails_helper"

RSpec.describe Transactions::CreateTransaction, type: :service do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:, kind: "expense") }

  let(:valid_params) do
    { description: "Groceries", kind: "expense", amount: 120.50, date: Date.current,
      account_id: account.id, category_id: category.id }
  end

  it "creates a transaction owned by the user" do
    result = nil
    expect { result = described_class.call(user:, params: valid_params) }
      .to change(user.transactions, :count).by(1)
    expect(result).to be_success
    expect(result.data).to be_a(Transaction)
  end

  it "returns validation errors as a failure" do
    result = described_class.call(user:, params: valid_params.merge(amount: -1))
    expect(result).to be_failure
    expect(result.errors).to be_present
  end

  it "fails when a referenced record does not exist" do
    result = described_class.call(user:, params: valid_params.merge(category_id: 0))
    expect(result).to be_failure
  end

  it "accepts symbol or string keys" do
    result = described_class.call(user:, params: valid_params.stringify_keys)
    expect(result).to be_success
  end
end
