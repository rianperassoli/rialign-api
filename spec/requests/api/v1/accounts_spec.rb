require "rails_helper"

RSpec.describe "Api::V1::Accounts", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/accounts" do
    it "lists the user's accounts, paginated" do
      create_list(:account, 2, user:)
      create(:account) # another user's
      get "/api/v1/accounts", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json.dig("meta", "pagination", "count")).to eq(2)
    end

    it "honours a custom items page size" do
      create_list(:account, 3, user:)
      get "/api/v1/accounts", params: { items: 1 }, headers: auth_headers(user)
      expect(json["data"].size).to eq(1)
      expect(json.dig("meta", "pagination", "items")).to eq(1)
    end
  end

  describe "POST /api/v1/accounts" do
    it "creates an account" do
      params = { account: { name: "Savings", account_type: "savings", initial_balance: 500 } }
      expect { post "/api/v1/accounts", params: params.to_json, headers: auth_headers(user) }
        .to change(user.accounts, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "current_balance")).to eq("500.0")
    end

    it "returns 422 on invalid input" do
      params = { account: { name: "", account_type: "nope" } }
      post "/api/v1/accounts", params: params.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when the account param is missing" do
      post "/api/v1/accounts", params: { foo: "bar" }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:bad_request)
      expect(json["message"]).to eq("Missing parameter")
    end
  end

  describe "GET /api/v1/accounts/:id" do
    it "shows an owned account" do
      account = create(:account, user:)
      get "/api/v1/accounts/#{account.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "id")).to eq(account.id)
    end

    it "returns 404 for another user's account" do
      account = create(:account)
      get "/api/v1/accounts/#{account.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/accounts/:id" do
    it "updates an account" do
      account = create(:account, user:)
      patch "/api/v1/accounts/#{account.id}", params: { account: { name: "Renamed" } }.to_json,
                                              headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(account.reload.name).to eq("Renamed")
    end
  end

  describe "DELETE /api/v1/accounts/:id" do
    it "soft deletes and returns 204" do
      account = create(:account, user:)
      delete "/api/v1/accounts/#{account.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(account.reload).to be_archived
      expect(Account.kept).not_to include(account)
    end
  end
end
