require "rails_helper"

# Every API route, read from the router so a new one is covered the day it is
# added: none answers without a login, none reaches another user's records by
# id, and no list or summary shows them.
RSpec.describe "Authorization sweep", type: :request do
  let(:user) { create(:user) }
  let(:intruder) { create(:user) }

  # The only routes meant to answer without a login.
  def public_routes
    ["POST /api/v1/auth/register", "POST /api/v1/auth/login"]
  end

  def api_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      next unless path.start_with?("/api/v1")

      "#{route.verb} #{path}" unless public_routes.include?("#{route.verb} #{path}")
    end.uniq
  end

  # The owner's records, one per resource, named as the routes name them.
  def owned_ids
    account = create(:account, user:)
    card = create(:credit_card, user:, payment_account: account)
    category = create(:category, user:)
    transaction = create(:transaction, user:, account:, category:)
    transfer_id = Transfers::CreateTransfer.call(user:, params: { from_account_id: account.id,
                                                                  to_account_id: create(:account, user:).id,
                                                                  amount: 10 }).data[:transfer_id]
    { "accounts" => account.id, "credit_cards" => card.id, "categories" => category.id,
      "transactions" => transaction.id, "transfers" => transfer_id, "imports" => create(:import, user:).id }
  end

  def call(verb, path, headers)
    send(verb.downcase, path, params: {}.to_json, headers:)
  end

  it "covers every route the API has" do
    expect(api_routes.size).to be >= 30
  end

  it "answers 401 on every route without a login" do
    api_routes.each do |route|
      verb, path = route.split
      call(verb, path.gsub(":id", "1"), { "Content-Type" => "application/json" })
      expect(response).to have_http_status(:unauthorized), "#{route} answered #{response.status}"
    end
  end

  it "never reaches another user's record by id" do
    ids = owned_ids
    api_routes.select { |route| route.include?(":id") }.each do |route|
      verb, path = route.split
      resource = path.split("/")[3]
      call(verb, path.sub(":id", ids.fetch(resource).to_s), auth_headers(intruder))

      expect(response).to have_http_status(:not_found), "#{route} answered #{response.status}"
    end
    expect(user.transactions.count).to eq(3) # nothing was changed or removed
  end

  it "never lists or sums another user's records" do
    owned_ids
    lists = %w[/accounts /credit_cards /categories /transactions /transfers /imports]
    lists.each do |path|
      get "/api/v1#{path}", headers: auth_headers(intruder)
      expect(json["data"]).to be_empty, "#{path} leaked #{json["data"].size} rows"
    end

    get "/api/v1/dashboard", headers: auth_headers(intruder)
    expect(json["data"]).to include("accounts" => [], "credit_cards" => [], "by_category" => [],
                                    "consolidated_balance" => "0.0")
  end
end
