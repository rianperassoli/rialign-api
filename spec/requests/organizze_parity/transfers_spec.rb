require "rails_helper"

# Moving money between one's own accounts, through the API, against Organizze:
# a transfer moves both balances, leaves "Saldo geral" as it was and is never
# income or expense.
RSpec.describe "Organizze parity: transfers", type: :request do
  include OrganizzeScenario

  let(:user) { create(:user) }
  let(:nubank) { account("NuBank", initial_balance: 2000) }
  let(:wallet) { account("Carteira", initial_balance: 0) }

  before { travel_to Date.new(2026, 10, 15) }

  def transfer_id
    api(:get, "/transfers", expect: :ok)["data"].sole["transfer_id"]
  end

  it "moves both balances, keeps Saldo geral and stays out of income and expense" do
    transfer(nubank, wallet, 300, date: "2026-10-10", description: "Saque")

    data = dashboard("2026-10")
    expect([balance_of(nubank), balance_of(wallet)]).to eq([1700, 300])
    expect(money(data["consolidated_balance"])).to eq(2000)
    expect(data["totals"].values.map { |v| money(v) }).to eq([0, 0, 0])
    expect(api(:get, "/transfers")["data"].sole).to include("from_account_id" => nubank, "to_account_id" => wallet)
  end

  it "lowers Saldo geral when the money goes to an account left out of it" do
    reserve = account("Reserva", exclude_from_total: true)
    transfer(nubank, reserve, 500, date: "2026-10-10")

    expect(money(dashboard("2026-10")["consolidated_balance"])).to eq(1500)
  end

  it "is edited as a whole and never one side alone" do
    transfer(nubank, wallet, 300, date: "2026-10-10")
    legs = transactions(search: "Transfer")

    api(:patch, "/transactions/#{legs.first["id"]}", { transaction: { amount: 1 } }, expect: :unprocessable_entity)
    api(:patch, "/transfers/#{transfer_id}", { transfer: { amount: 250 } }, expect: :ok)

    expect([balance_of(nubank), balance_of(wallet)]).to eq([1750, 250])
  end

  it "is deleted as a whole, from either side" do
    transfer(nubank, wallet, 300, date: "2026-10-10")
    api(:delete, "/transactions/#{transactions(search: "Transfer").first["id"]}", expect: :no_content)

    expect([balance_of(nubank), balance_of(wallet)]).to eq([2000, 0])
    expect(api(:get, "/transfers")["data"]).to be_empty
  end

  it "refuses moving money to the same account" do
    api(:post, "/transfers", { transfer: { from_account_id: nubank, to_account_id: nubank, amount: 10 } })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  # Organizze has no currencies; Rialign moves each side its own amount.
  it "moves each side its own amount between currencies" do
    dollars = account("Global", currency: "USD")
    api(:post, "/transfers", { transfer: { from_account_id: nubank, to_account_id: dollars, amount: 550 } },
        expect: :unprocessable_entity)

    transfer(nubank, dollars, 550, date: "2026-10-10", received_amount: 100)
    expect([balance_of(nubank), balance_of(dollars)]).to eq([1450, 100])
  end
end
