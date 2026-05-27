require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it { is_expected.to have_many(:accounts).dependent(:destroy) }
  it { is_expected.to have_many(:credit_cards).dependent(:destroy) }
  it { is_expected.to have_many(:categories).dependent(:destroy) }
  it { is_expected.to have_many(:transactions).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:email) }

  it "validates a minimum password length" do
    expect(build(:user, password: "short", password_confirmation: "short")).to be_invalid
  end

  it "rejects a malformed email" do
    expect(build(:user, email: "not-an-email")).to be_invalid
  end

  describe "email normalization" do
    it "downcases and strips before validation" do
      user = create(:user, email: "  MixedCase@Example.COM ")
      expect(user.email).to eq("mixedcase@example.com")
    end

    it "enforces case-insensitive uniqueness" do
      create(:user, email: "dup@example.com")
      expect(build(:user, email: "DUP@example.com")).to be_invalid
    end
  end

  it "authenticates with the correct password" do
    user = create(:user, password: "password123", password_confirmation: "password123")
    expect(user.authenticate("password123")).to be_truthy
    expect(user.authenticate("wrong")).to be_falsey
  end
end
