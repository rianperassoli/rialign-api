require "rails_helper"

RSpec.describe Auth::AuthenticateUser, type: :service do
  let!(:user) do
    create(:user, email: "user@example.com", password: "password123", password_confirmation: "password123")
  end

  it "returns a token for valid credentials" do
    result = described_class.call(email: "user@example.com", password: "password123")
    expect(result).to be_success
    expect(result.data[:user]).to eq(user)
    expect(result.data[:token]).to be_present
  end

  it "is case/whitespace insensitive on the email" do
    result = described_class.call(email: "  USER@example.com ", password: "password123")
    expect(result).to be_success
  end

  it "fails on a wrong password" do
    result = described_class.call(email: "user@example.com", password: "wrong")
    expect(result).to be_failure
    expect(result.errors).to eq(["Invalid email or password"])
  end

  it "fails on an unknown email" do
    result = described_class.call(email: "nobody@example.com", password: "password123")
    expect(result).to be_failure
  end
end
