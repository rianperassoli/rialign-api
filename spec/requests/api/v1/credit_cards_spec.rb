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

  describe "credit_card payment account" do
    let(:account) { create(:account, user:) }

    it "stores the payment account on create" do
      params = { credit_card: { name: "Nubank", credit_limit: 1000, closing_day: 5, due_day: 12,
                                payment_account_id: account.id } }
      post "/api/v1/credit_cards", params: params.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "payment_account_id")).to eq(account.id)
    end
  end

  describe "POST /api/v1/credit_cards/:id/pay_invoice" do
    let(:account) { create(:account, user:, initial_balance: 1000) }
    let(:card) { create(:credit_card, user:, payment_account: account) }

    before do
      create(:transaction, user:, credit_card: card, account: nil, kind: "expense", amount: 300, paid: false)
    end

    it "settles the invoice and returns the settlement transaction" do
      post "/api/v1/credit_cards/#{card.id}/pay_invoice", headers: auth_headers(user)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "account_id")).to eq(account.id)
      expect(json.dig("data", "transfer_id")).to be_present
      expect(card.transactions.expense.pending.count).to eq(0)
    end

    it "accepts an explicit payment account" do
      other = create(:account, user:, name: "Other")
      params = { payment: { account_id: other.id } }
      post "/api/v1/credit_cards/#{card.id}/pay_invoice", params: params.to_json, headers: auth_headers(user)
      expect(json.dig("data", "account_id")).to eq(other.id)
    end

    it "returns 422 when there is no open invoice" do
      empty = create(:credit_card, user:, payment_account: account)
      post "/api/v1/credit_cards/#{empty.id}/pay_invoice", headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
