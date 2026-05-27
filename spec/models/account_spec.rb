require "rails_helper"

RSpec.describe Account, type: :model do
  subject(:account) { build(:account) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:transactions).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:account_type) }
  it { is_expected.to validate_inclusion_of(:account_type).in_array(described_class::ACCOUNT_TYPES) }

  it "requires a numeric initial balance" do
    expect(build(:account, initial_balance: "abc")).to be_invalid
  end

  describe "soft delete" do
    it "archives instead of deleting and hides from default scope" do
      account = create(:account)
      account.destroy
      expect(account.reload).to be_archived
      expect(described_class.kept).not_to include(account)
      expect(described_class.archived).to include(account)
    end

    it "can be restored" do
      account = create(:account)
      account.archive!
      account.restore!
      expect(account).not_to be_archived
    end

    it "archive! is a no-op when already archived" do
      account = create(:account)
      account.archive!
      expect { account.archive! }.not_to(change { account.reload.archived_at })
    end
  end
end
