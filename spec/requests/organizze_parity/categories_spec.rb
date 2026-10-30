require "rails_helper"

# Categories and subcategories through the API, against Organizze: spending on
# a subcategory adds into its parent in the month's breakdown and the reports,
# and archiving a category keeps its history.
RSpec.describe "Organizze parity: categories", type: :request do
  include OrganizzeScenario

  let(:user) { create(:user) }
  let(:nubank) { account("NuBank", initial_balance: 5000) }
  let(:food) { category("Alimentação") }
  let(:market) { category("Mercado", parent: food) }
  let(:restaurant) { category("Restaurante", parent: food) }
  let(:home) { category("Casa") }

  before do
    travel_to Date.new(2026, 10, 15)
    entry("Feira", 50, on: nubank, category: food, date: "2026-10-02")
    entry("Supermercado", 300, on: nubank, category: market, date: "2026-10-03")
    entry("Pizza", 90, on: nubank, category: restaurant, date: "2026-10-04")
    entry("Aluguel", 400, on: nubank, category: home, date: "2026-10-05")
  end

  it "adds subcategories into their parent in the month's breakdown, listing them" do
    food_row, home_row = dashboard("2026-10")["by_category"]

    expect([food_row["name"], money(food_row["total"])]).to eq(["Alimentação", 440])
    expect(food_row["children"].map do |c|
      [c["name"], money(c["total"])]
    end).to eq([["Mercado", 300], ["Restaurante", 90]])
    expect([home_row["name"], money(home_row["total"])]).to eq(["Casa", 400])
  end

  it "adds them up the same way in the reports" do
    rows = api(:get, "/reports?months=1", expect: :ok)["data"]["by_category"]
    expect(rows.map { |r| [r["name"], money(r["total"])] }).to eq([["Alimentação", 440], ["Casa", 400]])
  end

  it "finds a subcategory's entries when filtering by its parent" do
    expect(transactions(category_id: food).pluck("description")).to contain_exactly("Feira", "Supermercado", "Pizza")
  end

  it "keeps an archived category's history, but takes no new entries on it" do
    api(:delete, "/categories/#{home}", expect: :no_content)

    expect(dashboard("2026-10")["by_category"].pluck("name")).to include("Casa")
    rent = transactions(search: "Aluguel").sole
    api(:patch, "/transactions/#{rent["id"]}", { transaction: { description: "Aluguel outubro" } }, expect: :ok)
    api(:post, "/transactions", { transaction: { description: "Condomínio", kind: "expense", amount: 10,
                                                 date: "2026-10-06", account_id: nubank, category_id: home } },
        expect: :unprocessable_entity)
  end

  it "archives the subcategories with their parent" do
    api(:delete, "/categories/#{food}", expect: :no_content)
    expect(api(:get, "/categories")["data"].pluck("name")).to eq(["Casa"])
  end

  it "refuses an income category on an expense" do
    salary = category("Salário", kind: "income")
    api(:post, "/transactions", { transaction: { description: "X", kind: "expense", amount: 10, date: "2026-10-06",
                                                 account_id: nubank, category_id: salary } })
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
