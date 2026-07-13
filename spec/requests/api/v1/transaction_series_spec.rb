require "rails_helper"

RSpec.describe "Api::V1::Transactions series", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:, kind: "expense") }

  let(:payload) do
    {
      transaction: {
        description: "Sofa", kind: "expense", amount: 900,
        date: "2026-07-10", account_id: account.id, category_id: category.id
      }
    }
  end

  describe "POST /api/v1/transactions with installments" do
    it "creates the whole series and reports its size" do
      expect do
        post "/api/v1/transactions", params: payload.merge(installments: 3).to_json,
                                     headers: auth_headers(user)
      end.to change(user.transactions, :count).by(3)

      expect(response).to have_http_status(:created)
      expect(json.dig("meta", "series_count")).to eq(3)
      expect(json.dig("data", "installment_number")).to eq(1)
      expect(json.dig("data", "installment_total")).to eq(3)
    end
  end

  describe "POST /api/v1/transactions with fixed_months" do
    it "creates monthly occurrences without installment fields" do
      expect do
        post "/api/v1/transactions", params: payload.merge(fixed_months: 4).to_json,
                                     headers: auth_headers(user)
      end.to change(user.transactions, :count).by(4)

      expect(json.dig("meta", "series_count")).to eq(4)
      expect(json.dig("data", "installment_number")).to be_nil
      expect(json.dig("data", "series_id")).to be_present
    end

    it "rejects an invalid date without creating anything" do
      expect do
        post "/api/v1/transactions",
             params: payload.deep_merge(transaction: { date: "not-a-date" }).merge(fixed_months: 3).to_json,
             headers: auth_headers(user)
      end.not_to change(user.transactions, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/transactions/:id?scope=" do
    let!(:series) do
      Transactions::CreateSeries.call(user:, params: payload[:transaction], installments: 3).data
    end

    it "archives only the occurrence by default" do
      expect do
        delete "/api/v1/transactions/#{series.second.id}", headers: auth_headers(user)
      end.to change(user.transactions, :count).by(-1)
    end

    it "archives this and future occurrences with scope=future" do
      expect do
        delete "/api/v1/transactions/#{series.second.id}?scope=future", headers: auth_headers(user)
      end.to change(user.transactions, :count).by(-2)
      expect(user.transactions.find_by(id: series.first.id)).to be_present
    end

    it "archives the whole series with scope=series" do
      expect do
        delete "/api/v1/transactions/#{series.second.id}?scope=series", headers: auth_headers(user)
      end.to change(user.transactions, :count).by(-3)
    end
  end
end
