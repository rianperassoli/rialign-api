require "rails_helper"

RSpec.describe "Api::V1::CreditCards", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/credit_cards" do
    it "lists the user's cards" do
      create_list(:credit_card, 2, user:)
      get "/api/v1/credit_cards", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
    end
  end

  describe "POST /api/v1/credit_cards" do
    it "creates a card" do
      params = { credit_card: { name: "Master", credit_limit: 2000, closing_day: 10, due_day: 20 } }
      expect { post "/api/v1/credit_cards", params: params.to_json, headers: auth_headers(user) }
        .to change(user.credit_cards, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "available_limit")).to eq("2000.0")
    end

    it "returns 422 on invalid input" do
      params = { credit_card: { name: "X", closing_day: 99 } }
      post "/api/v1/credit_cards", params: params.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET/PATCH/DELETE /api/v1/credit_cards/:id" do
    let(:card) { create(:credit_card, user:) }

    it "shows a card" do
      get "/api/v1/credit_cards/#{card.id}", headers: auth_headers(user)
      expect(json.dig("data", "id")).to eq(card.id)
    end

    it "updates a card" do
      patch "/api/v1/credit_cards/#{card.id}", params: { credit_card: { name: "New" } }.to_json,
                                               headers: auth_headers(user)
      expect(card.reload.name).to eq("New")
    end

    it "soft deletes a card" do
      delete "/api/v1/credit_cards/#{card.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(card.reload).to be_archived
    end
  end
end
