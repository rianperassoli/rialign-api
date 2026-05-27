require "rails_helper"

RSpec.describe Auth::RegisterUser, type: :service do
  let(:params) do
    { name: "Jane", email: "jane@example.com", password: "password123", password_confirmation: "password123" }
  end

  describe ".call" do
    it "creates a user, seeds categories and returns a token" do
      result = nil
      expect { result = described_class.call(params:) }.to change(User, :count).by(1)

      expect(result).to be_success
      expect(result.data[:user]).to be_a(User)
      expect(result.data[:token]).to be_present
      expect(result.data[:user].categories.count).to be_positive
    end

    it "decodes the issued token back to the user id" do
      result = described_class.call(params:)
      payload = JsonWebToken.decode(result.data[:token])
      expect(payload[:user_id]).to eq(result.data[:user].id)
    end

    it "fails and rolls back on invalid params" do
      bad = params.merge(email: "nope")
      result = nil
      expect { result = described_class.call(params: bad) }.not_to change(User, :count)
      expect(result).to be_failure
      expect(result.errors).to be_present
    end
  end
end
