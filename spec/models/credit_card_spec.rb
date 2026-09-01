require "rails_helper"

RSpec.describe CreditCard, type: :model do
  subject(:credit_card) { build(:credit_card) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:payment_account).optional }
  it { is_expected.to have_many(:transactions).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }

  it "accepts a payment account owned by the same user" do
    user = create(:user)
    expect(build(:credit_card, user:, payment_account: create(:account, user:))).to be_valid
  end

  it "rejects a payment account owned by another user" do
    card = build(:credit_card, user: create(:user), payment_account: create(:account))
    expect(card).to be_invalid
    expect(card.errors[:payment_account]).to include("must belong to the same user")
  end

  it "rejects a negative credit limit" do
    expect(build(:credit_card, credit_limit: -1)).to be_invalid
  end

  it "rejects out-of-range closing/due days" do
    expect(build(:credit_card, closing_day: 0)).to be_invalid
    expect(build(:credit_card, due_day: 32)).to be_invalid
  end

  # The open invoice is bounded by the closing date; the limit is not. A charge
  # made after the card closed belongs to the next invoice, but it is already
  # spending against the limit.
  describe "invoice and limit" do
    subject(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1, credit_limit: 1000) }

    let(:user) { create(:user) }
    let(:category) { create(:category, user:) }

    def charge(amount, date, paid: false)
      create(:transaction, user:, category:, account: nil, credit_card: card, amount:, date:, paid:)
    end

    before { travel_to Date.new(2026, 5, 15) }

    it "counts pending charges within the cycle" do
      charge(100, Date.new(2026, 5, 10))
      expect(card.open_invoice).to eq(100)
    end

    it "still counts pending charges left over from an earlier cycle" do
      charge(100, Date.new(2026, 3, 5))
      expect(card.open_invoice).to eq(100)
    end

    it "excludes charges dated after the closing date" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      expect(card.open_invoice).to eq(100)
    end

    it "excludes charges already settled" do
      charge(100, Date.new(2026, 5, 10), paid: true)
      expect(card.open_invoice).to eq(0)
    end

    it "consumes the limit with every pending charge, next cycle included" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      expect(card.used_limit).to eq(170)
      expect(card.available_limit).to eq(830)
    end
  end

  it "soft deletes" do
    card = create(:credit_card)
    card.destroy
    expect(card.reload).to be_archived
  end
end
