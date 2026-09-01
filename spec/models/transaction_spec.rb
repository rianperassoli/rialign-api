require "rails_helper"

RSpec.describe Transaction, type: :model do
  subject(:transaction) { build(:transaction) }

  it { is_expected.to belong_to(:user) }
  # category is optional at the association level; presence is enforced
  # conditionally (see "category requirement" below) so transfer legs can skip it.
  it { is_expected.to belong_to(:account).optional }
  it { is_expected.to belong_to(:credit_card).optional }

  it { is_expected.to validate_presence_of(:description) }
  it { is_expected.to validate_presence_of(:date) }
  it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }

  describe "source validation" do
    let(:user) { create(:user) }

    it "is invalid without an account or credit card" do
      t = build(:transaction, user:, account: nil, credit_card: nil)
      expect(t).to be_invalid
      expect(t.errors[:base]).to include("must reference exactly one account or credit card")
    end

    it "is invalid with both account and credit card" do
      t = build(:transaction, user:, account: create(:account, user:), credit_card: create(:credit_card, user:))
      expect(t).to be_invalid
    end

    it "is invalid when the category kind does not match" do
      income_cat = create(:income_category, user:)
      t = build(:transaction, user:, kind: "expense", category: income_cat)
      expect(t).to be_invalid
      expect(t.errors[:category]).to include("kind must match the transaction kind")
    end

    it "is invalid when a credit card holds a non-expense" do
      card = create(:credit_card, user:)
      income_cat = create(:income_category, user:)
      t = build(:transaction, user:, kind: "income", account: nil, credit_card: card, category: income_cat)
      expect(t).to be_invalid
      expect(t.errors[:credit_card]).to include("can only hold expense transactions")
    end
  end

  describe "category requirement" do
    let(:user) { create(:user) }

    it "requires a category for a regular transaction" do
      t = build(:transaction, user:, category: nil)
      expect(t).to be_invalid
      expect(t.errors[:category]).to include("must be present")
    end

    it "allows a missing category on a transfer leg" do
      t = build(:transaction, user:, category: nil, transfer_id: SecureRandom.uuid,
                              account: create(:account, user:))
      expect(t).to be_valid
    end
  end

  describe "#signed_amount" do
    it "is positive for income" do
      expect(build(:income_transaction).signed_amount).to be > 0
    end

    it "is negative for expense" do
      expect(build(:transaction, amount: 50).signed_amount).to eq(-50)
    end
  end

  # `paid` has no column default: nil means "the caller did not say", and the
  # model fills it in from the source. A card charge is money not yet spent.
  describe "paid default" do
    let(:user) { create(:user) }
    let(:card) { create(:credit_card, user:) }

    def card_charge(paid:)
      create(:transaction, user:, account: nil, credit_card: card, paid:)
    end

    it "leaves a card charge pending when paid is not given" do
      expect(card_charge(paid: nil)).not_to be_paid
    end

    it "settles an account expense when paid is not given" do
      expect(create(:transaction, user:, paid: nil)).to be_paid
    end

    it "respects an explicitly settled card charge" do
      expect(card_charge(paid: true)).to be_paid
    end

    it "respects an explicitly pending account expense" do
      expect(create(:transaction, user:, paid: false)).not_to be_paid
    end
  end

  describe "soft delete" do
    it "archives instead of deleting" do
      t = create(:transaction)
      expect { t.destroy }.not_to change(described_class.unscoped, :count)
      expect(t.reload).to be_archived
      expect(described_class.kept).not_to include(t)
    end
  end
end
