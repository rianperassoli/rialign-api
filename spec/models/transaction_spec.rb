require "rails_helper"

RSpec.describe Transaction, type: :model do
  subject(:transaction) { build(:transaction) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:category) }
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
  end

  describe "#signed_amount" do
    it "is positive for income" do
      expect(build(:income_transaction).signed_amount).to be > 0
    end

    it "is negative for expense" do
      expect(build(:transaction, amount: 50).signed_amount).to eq(-50)
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
