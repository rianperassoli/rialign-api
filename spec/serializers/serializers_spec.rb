require "rails_helper"

RSpec.describe "Serializers" do
  let(:user) { create(:user) }

  describe ApplicationSerializer do
    it "requires subclasses to implement #attributes" do
      expect { described_class.new(Object.new).as_json }.to raise_error(NotImplementedError)
    end

    it ".collection maps each record" do
      out = UserSerializer.collection([user])
      expect(out).to all(include(:id, :email))
    end
  end

  describe UserSerializer do
    it "exposes safe public fields only" do
      json = described_class.new(user).as_json
      expect(json.keys).to contain_exactly(:id, :name, :email, :created_at)
    end
  end

  describe AccountSerializer do
    let(:account) { create(:account, user:, initial_balance: 100) }

    it "computes current_balance on demand" do
      create(:transaction, user:, account:, amount: 30, paid: true)
      expect(described_class.new(account).as_json[:current_balance]).to eq(70)
    end

    it "uses a provided balance to avoid recomputation" do
      expect(described_class.new(account, balance: 999).as_json[:current_balance]).to eq(999)
    end
  end

  describe CreditCardSerializer do
    let(:card) { create(:credit_card, user:, credit_limit: 1000) }

    it "computes the open invoice and available limit" do
      # Dated into a closed cycle so it is part of the invoice being billed now.
      create(:transaction, user:, account: nil, credit_card: card, amount: 250, paid: false, date: 2.months.ago)
      json = described_class.new(card).as_json
      expect(json[:open_invoice]).to eq(250)
      expect(json[:available_limit]).to eq(750)
    end

    it "accepts precomputed values to avoid recomputation" do
      json = described_class.new(card, open_invoice: 100, available_limit: 900).as_json
      expect(json[:open_invoice]).to eq(100)
      expect(json[:available_limit]).to eq(900)
    end
  end

  describe CategorySerializer do
    it "serializes the core fields" do
      category = create(:category, user:)
      expect(described_class.new(category).as_json).to include(kind: "expense", archived: false)
    end
  end

  describe TransactionSerializer do
    it "includes signed_amount and a nested category" do
      transaction = create(:transaction, user:, amount: 40)
      json = described_class.new(transaction).as_json
      expect(json[:signed_amount]).to eq(-40)
      expect(json[:category]).to include(:id, :name, :kind)
    end
  end

  describe DashboardSerializer do
    it "merges the query summary with balances, including accounts and cards" do
      create(:account, user:)
      create(:credit_card, user:)
      summary = DashboardQuery.new(user).call
      balances = Accounts::BalanceCalculator.call(user:).data
      json = described_class.new(summary, balances:).as_json
      expect(json).to include(:period, :totals, :forecast, :by_category, :consolidated_balance, :accounts,
                              :credit_cards)
      expect(json[:accounts].size).to eq(1)
      expect(json[:credit_cards].size).to eq(1)
    end
  end
end
