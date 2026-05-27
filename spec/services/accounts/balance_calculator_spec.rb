require "rails_helper"

RSpec.describe Accounts::BalanceCalculator, type: :service do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:, initial_balance: 1000) }

  before do
    create(:income_transaction, user:, account:, amount: 500, paid: true)
    create(:transaction, user:, account:, amount: 200, paid: true)
    create(:transaction, user:, account:, amount: 999, paid: false) # pending, ignored
  end

  describe "#account_balance" do
    it "is initial + paid income - paid expense" do
      result = described_class.new(user:)
      expect(result.account_balance(account)).to eq(1000 + 500 - 200)
    end
  end

  describe ".call" do
    it "returns the consolidated balance" do
      result = described_class.call(user:)
      expect(result).to be_success
      expect(result.data[:consolidated_balance]).to eq(1300)
    end
  end

  describe "credit card invoice" do
    let(:card) { create(:credit_card, user:, credit_limit: 5000) }

    it "sums unpaid card expenses as the open invoice" do
      create(:transaction, user:, account: nil, credit_card: card, amount: 300, paid: false)
      row = described_class.call(user:).data[:credit_cards].find { |r| r[:credit_card] == card }
      expect(row[:open_invoice]).to eq(300)
      expect(row[:available_limit]).to eq(4700)
    end
  end
end
