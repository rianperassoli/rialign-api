require "rails_helper"

RSpec.describe "Api::V1::Authentication", type: :request do
  describe "POST /api/v1/auth/register" do
    let(:params) do
      { name: "Jane", email: "jane@example.com", password: "password123", password_confirmation: "password123" }
    end

    it "creates a user and returns a token" do
      expect { post "/api/v1/auth/register", params: params.to_json, headers: { "Content-Type" => "application/json" } }
        .to change(User, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "token")).to be_present
      expect(json.dig("data", "user", "email")).to eq("jane@example.com")
    end

    it "returns 422 with errors on invalid input" do
      post "/api/v1/auth/register", params: params.merge(email: "bad").to_json,
                                    headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "POST /api/v1/auth/login" do
    before { create(:user, email: "demo@example.com", password: "password123", password_confirmation: "password123") }

    it "returns a token for valid credentials" do
      post "/api/v1/auth/login", params: { email: "demo@example.com", password: "password123" }.to_json,
                                 headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "token")).to be_present
    end

    it "returns 401 for bad credentials" do
      post "/api/v1/auth/login", params: { email: "demo@example.com", password: "nope" }.to_json,
                                 headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/auth/me" do
    let(:user) { create(:user) }

    it "returns the current user" do
      get "/api/v1/auth/me", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "id")).to eq(user.id)
    end

    it "rejects a missing token" do
      get "/api/v1/auth/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an invalid token" do
      get "/api/v1/auth/me", headers: { "Authorization" => "Bearer garbage" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
