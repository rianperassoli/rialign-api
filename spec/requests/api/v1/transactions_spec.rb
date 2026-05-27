require "rails_helper"

RSpec.describe "Api::V1::Transactions", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:, kind: "expense") }

  describe "POST /api/v1/transactions" do
    let(:payload) do
      {
        transaction: {
          description: "Groceries", kind: "expense", amount: 120.50,
          date: Date.current.to_s, account_id: account.id, category_id: category.id
        }
      }
    end

    it "creates a transaction" do
      expect do
        post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)
      end.to change(user.transactions, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "amount").to_f).to eq(120.50)
    end

    it "rejects an unauthenticated request" do
      post "/api/v1/transactions", params: payload.to_json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns validation errors" do
      payload[:transaction][:amount] = -5
      post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "GET /api/v1/transactions" do
    before { create_list(:transaction, 3, user:, account:, category:) }

    it "lists paginated transactions scoped to the user" do
      create(:transaction) # another user's transaction
      get "/api/v1/transactions", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(3)
      expect(json.dig("meta", "pagination", "count")).to eq(3)
    end
  end
end
