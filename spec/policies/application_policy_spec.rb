require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:user) { create(:user) }
  let(:other) { create(:user) }
  let(:account) { create(:account, user:) }

  it "grants access to the owner" do
    policy = described_class.new(user, account)
    expect(policy.owner?).to be(true)
    expect(policy.show?).to be(true)
    expect(policy.update?).to be(true)
    expect(policy.destroy?).to be(true)
  end

  it "denies a non-owner" do
    expect(described_class.new(other, account).owner?).to be(false)
  end

  it "denies when the record has no user_id" do
    expect(described_class.new(user, Object.new).owner?).to be(false)
  end

  it "denies when there is no user" do
    expect(described_class.new(nil, account).owner?).to be(false)
  end
end
