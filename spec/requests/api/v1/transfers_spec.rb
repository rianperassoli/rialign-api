require "rails_helper"

RSpec.describe "Api::V1::Transfers", type: :request do
  let(:user) { create(:user) }
  let(:from) { create(:account, user:, name: "Checking") }
  let(:to)   { create(:account, user:, name: "Savings") }

  describe "POST /api/v1/transfers" do
    it "creates a transfer (two legs)" do
      params = { transfer: { from_account_id: from.id, to_account_id: to.id, amount: 100, date: Date.current } }
      expect { post "/api/v1/transfers", params: params.to_json, headers: auth_headers(user) }
        .to change(user.transactions, :count).by(2)
      expect(response).to have_http_status(:created)
    end

    it "returns 422 on invalid input" do
      params = { transfer: { from_account_id: from.id, to_account_id: from.id, amount: 100 } }
      post "/api/v1/transfers", params: params.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/transfers" do
    it "lists one row per transfer" do
      Transfers::CreateTransfer.call(user:,
                                     params: { from_account_id: from.id,
                                               to_account_id: to.id, amount: 100, date: Date.current })
      get "/api/v1/transfers", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(1)
      expect(json["data"].first["transfer_id"]).to be_present
    end
  end

  describe "DELETE /api/v1/transfers/:id" do
    it "removes both legs" do
      result = Transfers::CreateTransfer.call(user:,
                                              params: {
                                                from_account_id: from.id, to_account_id: to.id,
                                                amount: 100, date: Date.current
                                              })
      transfer_id = result.data[:transfer_id]

      delete "/api/v1/transfers/#{transfer_id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(user.transactions.where(transfer_id:)).to be_empty
    end

    it "returns 404 for an unknown transfer" do
      delete "/api/v1/transfers/#{SecureRandom.uuid}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
