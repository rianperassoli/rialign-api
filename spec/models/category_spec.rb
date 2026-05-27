require "rails_helper"

RSpec.describe Category, type: :model do
  subject(:category) { build(:category) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:transactions).dependent(:restrict_with_error) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:kind) }
  it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }

  it "soft deletes even when it has transactions" do
    transaction = create(:transaction)
    category = transaction.category
    expect { category.destroy }.not_to raise_error
    expect(category.reload).to be_archived
  end
end
