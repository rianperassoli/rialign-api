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

    it "refuses to book on another user's account, leaving its balance alone" do
      victim = create(:account, initial_balance: 500)
      payload[:transaction][:account_id] = victim.id

      post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Accounts::BalanceCalculator.new(user: victim.user).account_balance(victim)).to eq(500)
    end

    it "returns validation errors" do
      payload[:transaction][:amount] = -5
      post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "GET /api/v1/transactions/export" do
    it "sends the filtered list as a CSV file" do
      create(:transaction, user:, account:, category:, description: "Mercado", amount: 50)
      create(:transaction, user:, account:, category:, description: "Aluguel", amount: 900)

      get "/api/v1/transactions/export?search=Merc", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("lancamentos-")
      expect(response.body.lines.size).to eq(2)
    end
  end

  describe "GET /api/v1/transactions" do
    before { create_list(:transaction, 3, user:, account:, category:) }

    it "lists a transfer once, from its source, unless narrowed to the destination" do
      savings = create(:account, user:, name: "Savings")
      Transfers::CreateTransfer.call(user:, params: { from_account_id: account.id, to_account_id: savings.id,
                                                      amount: 50, date: Date.current })

      get "/api/v1/transactions", headers: auth_headers(user)
      transfer = json["data"].select { |row| row["transfer_id"] }
      expect(transfer.map { |row| row.values_at("kind", "account_id", "counterpart_account_id") })
        .to eq([["expense", account.id, savings.id]])

      get "/api/v1/transactions?account_id=#{savings.id}", headers: auth_headers(user)
      expect(json["data"].map { |row| row.values_at("kind", "counterpart_account_id") })
        .to eq([["income", account.id]])
    end

    it "lists the open invoices among the cash flow, unless the filters rule them out" do
      card = create(:credit_card, user:, closing_day: 31, due_day: 10)
      create(:transaction, user:, account: nil, credit_card: card, amount: 80, paid: false,
                           date: Date.new(2026, 10, 5), invoice_month: Date.new(2026, 11, 1))
      period = "view=cash_flow&from=2026-11-01&to=2026-11-30"

      get "/api/v1/transactions?#{period}", headers: auth_headers(user)
      expect(json.dig("meta", "open_invoices").sole).to include("due_date" => "2026-11-10", "amount" => "80.0")

      get "/api/v1/transactions?#{period}&type=expense&paid=false", headers: auth_headers(user)
      expect(json.dig("meta", "open_invoices").size).to eq(1)

      ["&type=income", "&search=x", "&paid=true", "&kind=income"].each do |narrowing|
        get "/api/v1/transactions?#{period}#{narrowing}", headers: auth_headers(user)
        expect(json["meta"]).not_to have_key("open_invoices")
      end

      get "/api/v1/transactions?view=cash_flow&from=bad&to=worse", headers: auth_headers(user)
      expect(json["meta"]).not_to have_key("open_invoices")
    end

    it "lists paginated transactions scoped to the user" do
      create(:transaction) # another user's transaction
      get "/api/v1/transactions", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(3)
      expect(json.dig("meta", "pagination", "count")).to eq(3)
    end

    it "adds what the whole filtered list sums to, beyond the page" do
      create(:income_transaction, user:, account:, description: "Pai gasolina", amount: 100)
      create(:transaction, user:, account:, description: "To savings", amount: 999, transfer_id: SecureRandom.uuid,
                           category: nil)
      get "/api/v1/transactions?items=1", headers: auth_headers(user)
      expense = user.transactions.non_transfer.expense.sum(:amount) # the transfer leg stays out

      expect(json["data"].size).to eq(1)
      expect(json.dig("meta", "totals").transform_values(&:to_f))
        .to eq("income" => 100.0, "expense" => expense.to_f, "net" => (100 - expense).to_f)

      get "/api/v1/transactions?search=gasolina", headers: auth_headers(user)
      expect(json.dig("meta", "totals").transform_values(&:to_f))
        .to eq("income" => 100.0, "expense" => 0.0, "net" => 100.0)
    end
  end

  describe "GET /api/v1/transactions/:id" do
    it "shows an owned transaction" do
      transaction = create(:transaction, user:, account:, category:)
      get "/api/v1/transactions/#{transaction.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "id")).to eq(transaction.id)
    end

    it "returns 404 for another user's transaction" do
      get "/api/v1/transactions/#{create(:transaction).id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "open-ended fixed entries" do
    let(:payload) do
      { fixed: true, transaction: { description: "Academia", kind: "expense", amount: 99,
                                    date: Date.current.to_s, account_id: account.id, category_id: category.id } }
    end

    it "creates a year of occurrences and keeps extending them on later requests" do
      post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:created)
      expect(user.transactions.count).to eq(13)

      travel_to(2.months.from_now) do
        get "/api/v1/transactions", headers: auth_headers(user)
        expect(user.transactions.count).to eq(15)
      end
    end

    it "stops when this and the following occurrences are deleted" do
      post "/api/v1/transactions", params: payload.to_json, headers: auth_headers(user)
      third = user.transactions.order(:date).third

      delete "/api/v1/transactions/#{third.id}?scope=future", headers: auth_headers(user)
      expect(user.recurrences).to be_empty
      expect(user.transactions.count).to eq(2)
    end
  end

  describe "PATCH /api/v1/transactions/:id with a scope" do
    let!(:series) do
      Transactions::CreateSeries.call(user:, months: 3,
                                      params: { description: "Netflix", kind: "expense", amount: 40,
                                                date: Date.current.to_s, account_id: account.id,
                                                category_id: category.id }).data
    end

    def patch_scoped(scope, description)
      patch "/api/v1/transactions/#{series.first.id}?scope=#{scope}",
            params: { transaction: { description: } }.to_json, headers: auth_headers(user)
    end

    it "edits only the occurrence by default" do
      patch_scoped("one", "Max")
      expect(series.map { |t| t.reload.description }).to eq(%w[Max Netflix Netflix])
    end

    it "edits the whole series with scope=series" do
      patch_scoped("series", "Max")
      expect(response).to have_http_status(:ok)
      expect(series.map { |t| t.reload.description }.uniq).to eq(["Max"])
    end

    it "returns 422 when the series cannot take the change" do
      patch "/api/v1/transactions/#{series.first.id}?scope=series",
            params: { transaction: { amount: 0 } }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/transactions/:id" do
    it "updates a transaction" do
      transaction = create(:transaction, user:, account:, category:)
      patch "/api/v1/transactions/#{transaction.id}",
            params: { transaction: { description: "Updated" } }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(transaction.reload.description).to eq("Updated")
    end

    it "moves a card charge to another invoice" do
      card = create(:credit_card, user:, closing_day: 31, due_day: 10)
      charge = create(:transaction, user:, account: nil, credit_card: card, category:, date: Date.new(2026, 10, 7))
      patch "/api/v1/transactions/#{charge.id}",
            params: { transaction: { invoice_month: "2026-12" } }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "invoice_month")).to eq("2026-12")
      expect(charge.reload.invoice_month).to eq(Date.new(2026, 12, 1))
    end

    it "refuses to move a card charge onto a paid invoice" do
      card = create(:credit_card, user:, closing_day: 31, due_day: 10)
      create(:transaction, user:, account: nil, credit_card: card, category:, date: Date.new(2026, 9, 7), paid: true)
      charge = create(:transaction, user:, account: nil, credit_card: card, category:, date: Date.new(2026, 10, 7))
      patch "/api/v1/transactions/#{charge.id}",
            params: { transaction: { invoice_month: "2026-10" } }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_content)
      expect(charge.reload.invoice_month).to eq(Date.new(2026, 11, 1))
    end

    it "still moves a card charge onto a closed but unpaid invoice" do
      card = create(:credit_card, user:, closing_day: 31, due_day: 10)
      create(:transaction, user:, account: nil, credit_card: card, category:, date: Date.new(2026, 9, 7), paid: false)
      charge = create(:transaction, user:, account: nil, credit_card: card, category:, date: Date.new(2026, 10, 7))
      patch "/api/v1/transactions/#{charge.id}",
            params: { transaction: { invoice_month: "2026-10" } }.to_json, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(charge.reload.invoice_month).to eq(Date.new(2026, 10, 1))
    end
  end

  describe "DELETE /api/v1/transactions/:id" do
    it "soft deletes a transaction" do
      transaction = create(:transaction, user:, account:, category:)
      delete "/api/v1/transactions/#{transaction.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(transaction.reload).to be_archived
    end
  end
end
