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

  describe "a single transfer" do
    let(:transfer_id) do
      Transfers::CreateTransfer.call(user:, params: { from_account_id: from.id, to_account_id: to.id,
                                                      amount: 100, date: Date.current }).data[:transfer_id]
    end

    it "shows it as one movement" do
      get "/api/v1/transfers/#{transfer_id}", headers: auth_headers(user)
      expect(json["data"]).to include("transfer_id" => transfer_id, "from_account_id" => from.id,
                                      "to_account_id" => to.id)
    end

    it "shows an unpaired leg with only its own side" do
      %w[expense income].each do |kind|
        leg = user.transactions.create!(account: from, kind:, amount: 40, date: Date.current,
                                        description: "Pix", transfer_id: SecureRandom.uuid)
        get "/api/v1/transfers/#{leg.transfer_id}", headers: auth_headers(user)
        side = kind == "income" ? "to_account_id" : "from_account_id"
        expect(json["data"].slice("from_account_id", "to_account_id").compact).to eq(side => from.id)
      end
    end

    it "updates both legs" do
      patch "/api/v1/transfers/#{transfer_id}", params: { transfer: { amount: 30 } }.to_json,
                                                headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(user.transactions.where(transfer_id:).pluck(:amount)).to eq([30, 30])
    end

    it "returns 422 when the change is refused" do
      patch "/api/v1/transfers/#{transfer_id}", params: { transfer: { to_account_id: from.id } }.to_json,
                                                headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 for another user's transfer" do
      get "/api/v1/transfers/#{transfer_id}", headers: auth_headers(create(:user))
      expect(response).to have_http_status(:not_found)
    end

    it "refuses editing one leg's amount through transactions, and deleting a leg removes both" do
      leg = user.transactions.where(transfer_id:).first
      patch "/api/v1/transactions/#{leg.id}", params: { transaction: { amount: 5 } }.to_json,
                                              headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)

      delete "/api/v1/transactions/#{leg.id}", headers: auth_headers(user)
      expect(user.transactions.where(transfer_id:)).to be_empty
    end
  end

  describe "GET /api/v1/transfers" do
    it "lists each transfer once with both sides, skipping invoice payments" do
      Transfers::CreateTransfer.call(user:, params: { from_account_id: from.id, to_account_id: to.id,
                                                      amount: 100, date: Date.current })
      lone = user.transactions.create!(account: to, kind: "income", amount: 7, date: Date.current - 1,
                                       description: "Pix", transfer_id: SecureRandom.uuid)
      card = create(:credit_card, user:, payment_account: from)
      create(:transaction, user:, credit_card: card, account: nil, amount: 50, paid: false)
      CreditCards::PayInvoice.call(user:, credit_card: card,
                                   params: { month: card.current_invoice_month.strftime("%Y-%m") })

      get "/api/v1/transfers", headers: auth_headers(user)

      expect(json["data"].map { |row| row.slice("from_account_id", "to_account_id", "transfer_id") }).to eq(
        [{ "from_account_id" => from.id, "to_account_id" => to.id,
           "transfer_id" => json.dig("data", 0, "transfer_id") },
         { "from_account_id" => nil, "to_account_id" => to.id, "transfer_id" => lone.transfer_id }]
      )
      expect(json.dig("meta", "pagination", "count")).to eq(2)
    end

    # An imported invoice paid in two goes: two account legs sharing the
    # transfer_id, only one of them pointed at by the charges.
    it "skips every leg of an invoice payment" do
      card = create(:credit_card, user:)
      transfer_id = SecureRandom.uuid
      first, = [60, 40].map do |amount|
        user.transactions.create!(account: from, kind: "expense", amount:, date: Date.current, paid: true,
                                  description: "Pagamento de fatura", transfer_id:)
      end
      create(:transaction, user:, credit_card: card, account: nil, amount: 100, paid: true, settled_by: first)

      get "/api/v1/transfers", headers: auth_headers(user)

      expect(json["data"]).to be_empty
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
