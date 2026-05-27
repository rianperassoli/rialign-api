require "rails_helper"

RSpec.describe "Api::V1::Dashboard", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:, initial_balance: 1000) }

  before do
    create(:income_transaction, user:, account:, amount: 2000, date: Date.current, paid: true)
    create(:transaction, user:, account:, amount: 300, date: Date.current, paid: true)
  end

  describe "GET /api/v1/dashboard" do
    it "returns the monthly summary and balances" do
      get "/api/v1/dashboard", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "totals", "net")).to eq("1700.0")
      expect(json.dig("data", "consolidated_balance")).to eq("2700.0")
    end

    it "accepts a month parameter" do
      get "/api/v1/dashboard", params: { month: "2026-05" }, headers: auth_headers(user)
      expect(json.dig("data", "period", "from")).to eq("2026-05-01")
    end

    it "ignores a malformed month and uses the current month" do
      get "/api/v1/dashboard", params: { month: "garbage" }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "period", "from")).to eq(Date.current.beginning_of_month.to_s)
    end

    it "requires authentication" do
      get "/api/v1/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/dashboard/balances" do
    it "returns consolidated balance with accounts and cards" do
      create(:credit_card, user:)
      get "/api/v1/dashboard/balances", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "consolidated_balance")).to eq("2700.0")
      expect(json.dig("data", "accounts").size).to eq(1)
      expect(json.dig("data", "credit_cards").size).to eq(1)
    end
  end
end
