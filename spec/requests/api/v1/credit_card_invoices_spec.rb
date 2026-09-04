require "rails_helper"

RSpec.describe "Api::V1::CreditCards invoices", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1, payment_account: account) }
  let(:category) { create(:category, user:) }

  before do
    create(:transaction, user:, category:, account: nil, credit_card: card,
                         amount: 100, date: Date.new(2026, 5, 5), paid: false)
    create(:transaction, user:, category:, account: nil, credit_card: card,
                         amount: 40, date: Date.new(2026, 6, 5), paid: false)
  end

  # Closing on the 20th and due on the 1st, so the invoice due in June is the
  # cycle 21/04 to 20/05 — the one holding the 05/05 charge.
  describe "GET /api/v1/credit_cards/:id/invoice" do
    it "returns the requested month's cycle" do
      get "/api/v1/credit_cards/#{card.id}/invoice?month=2026-06", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "month")).to eq("2026-06")
      expect(json.dig("data", "total").to_f).to eq(100)
      expect(json.dig("data", "due_date")).to eq("2026-06-01")
      expect(json.dig("data", "transactions").size).to eq(1)
    end

    it "defaults to the current month when the param is missing" do
      get "/api/v1/credit_cards/#{card.id}/invoice", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "month")).to eq(Date.current.strftime("%Y-%m"))
    end

    it "defaults to the current month when the param is invalid" do
      get "/api/v1/credit_cards/#{card.id}/invoice?month=bogus", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "month")).to eq(Date.current.strftime("%Y-%m"))
    end
  end

  describe "POST /api/v1/credit_cards/:id/pay_invoice with a month" do
    it "settles only charges up to that invoice's closing date" do
      post "/api/v1/credit_cards/#{card.id}/pay_invoice",
           params: { payment: { month: "2026-06" } }.to_json,
           headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      expect(card.transactions.pending.sum(:amount)).to eq(40)
    end

    it "ignores an invalid month and settles everything" do
      post "/api/v1/credit_cards/#{card.id}/pay_invoice",
           params: { payment: { month: "bogus" } }.to_json,
           headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      expect(card.transactions.pending.count).to eq(0)
    end
  end
end
