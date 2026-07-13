require "rails_helper"

RSpec.describe "Api::V1::Reports", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:) }

  before do
    create(:transaction, user:, account:, category:, amount: 100, date: Date.current)
  end

  describe "GET /api/v1/reports" do
    it "returns the monthly evolution and category breakdown" do
      get "/api/v1/reports?months=3", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "monthly").size).to eq(3)
      expect(json.dig("data", "monthly").last["expense"].to_f).to eq(100)
      expect(json.dig("data", "by_category").first["name"]).to eq(category.name)
    end

    it "falls back to the default window on invalid months" do
      get "/api/v1/reports?months=999", headers: auth_headers(user)
      expect(json.dig("data", "monthly").size).to eq(6)
    end

    it "rejects an unauthenticated request" do
      get "/api/v1/reports"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
