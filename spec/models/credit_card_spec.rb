require "rails_helper"

RSpec.describe CreditCard, type: :model do
  subject(:credit_card) { build(:credit_card) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:transactions).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }

  it "rejects a negative credit limit" do
    expect(build(:credit_card, credit_limit: -1)).to be_invalid
  end

  it "rejects out-of-range closing/due days" do
    expect(build(:credit_card, closing_day: 0)).to be_invalid
    expect(build(:credit_card, due_day: 32)).to be_invalid
  end

  it "soft deletes" do
    card = create(:credit_card)
    card.destroy
    expect(card.reload).to be_archived
  end
end
