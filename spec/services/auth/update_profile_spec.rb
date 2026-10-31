require "rails_helper"

RSpec.describe Auth::UpdateProfile, type: :service do
  let(:user) { create(:user, name: "Old Name", email: "me@example.com") }

  it "changes the name" do
    result = described_class.call(user:, params: { name: "New Name" })

    expect(result).to be_success
    expect(user.reload.name).to eq("New Name")
  end

  it "never changes the email" do
    described_class.call(user:, params: { name: "New Name", email: "other@example.com" })

    expect(user.reload.email).to eq("me@example.com")
  end

  it "fails on a blank name and keeps the old one" do
    result = described_class.call(user:, params: { name: "  " })

    expect(result).to be_failure
    expect(result.errors).to be_present
    expect(user.reload.name).to eq("Old Name")
  end
end
