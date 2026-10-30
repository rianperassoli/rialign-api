require "rails_helper"

RSpec.describe "Api::V1::Reports", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:) }

  before do
    create(:transaction, user:, account:, category:, amount: 100, date: Date.current)
  end

  it "rejects an unauthenticated request" do
    get "/api/v1/reports/categories"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/reports/categories" do
    it "returns the period's expenses and income by category" do
      get "/api/v1/reports/categories?basis=invoice", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "basis")).to eq("invoice")
      expect(json.dig("data", "expense").first["name"]).to eq(category.name)
      expect(json.dig("data", "income")).to eq([])
    end

    it "reads the filters from comma-separated lists" do
      get "/api/v1/reports/categories?category_ids=#{category.id},x&account_ids=0&status=unpaid",
          headers: auth_headers(user)
      expect(json.dig("data", "expense")).to eq([])
    end
  end

  describe "GET /api/v1/reports/cash_flow" do
    it "returns the period's money in and out, by day" do
      get "/api/v1/reports/cash_flow?from=2026-10-01&to=2026-10-03&group=day", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "rows").size).to eq(3)
      expect(json.dig("data", "period")).to eq("from" => "2026-10-01", "to" => "2026-10-03")
    end

    it "defaults to the current month, puts the dates in order and caps the span" do
      get "/api/v1/reports/cash_flow?group=total", headers: auth_headers(user)
      expect(json.dig("data", "period", "from")).to eq(Date.current.beginning_of_month.iso8601)

      get "/api/v1/reports/cash_flow?from=2026-10-31&to=2026-10-01&group=total", headers: auth_headers(user)
      expect(json.dig("data", "period")).to eq("from" => "2026-10-01", "to" => "2026-10-31")

      get "/api/v1/reports/cash_flow?from=2000-01-01&to=2030-01-01&group=total&unpaid=1", headers: auth_headers(user)
      expect(json.dig("data", "period", "to")).to eq((Date.new(2000, 1, 1) + 1830).iso8601)
    end

    it "reads a single account, and only the user's own" do
      get "/api/v1/reports/cash_flow?group=total&account_id=#{account.id}&from=garbage", headers: auth_headers(user)
      expect(json.dig("data", "totals", "expense").to_f).to eq(100)

      get "/api/v1/reports/cash_flow?account_id=#{create(:account).id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
