require "rails_helper"

# One month of a typical user, built through the API, against what Organizze's
# dashboard shows for the same month: "Saldo geral", each account's balance,
# "Receita mensal" / "Despesa mensal" and the card summary.
#
# Card spending counts in the month its invoice is due, paid or not — verified
# against a real Organizze dashboard to the cent.
RSpec.describe "Organizze parity: dashboard", type: :request do
  include OrganizzeScenario

  let(:user) { create(:user) }
  let(:nubank) { account("NuBank", initial_balance: 1000) }
  let(:wallet) { account("Carteira", initial_balance: 200) }
  let(:salary) { category("Salário", kind: "income") }
  let(:home) { category("Casa") }
  let(:shopping) { category("Compras") }
  # Closes on the 3rd, due on the 10th: a purchase up to the 3rd goes on that
  # month's invoice, one after it on the next month's.
  let(:card_id) { card("NuBank - Cartão", limit: 5000, closing_day: 3, due_day: 10, payment_account: nubank) }

  before do
    travel_to Date.new(2026, 10, 15)

    income("Salário", 5000, on: nubank, category: salary, date: "2026-10-05")
    entry("Aluguel", 1500, on: nubank, category: home, date: "2026-10-06")
    entry("Luz", 300, on: nubank, category: home, date: "2026-10-20", paid: false) # scheduled
    transfer(nubank, wallet, 100, date: "2026-10-07")

    entry("Mercado", 400, on: { credit_card_id: card_id }, category: shopping, date: "2026-10-02") # Oct invoice
    entry("Livro", 250, on: { credit_card_id: card_id }, category: shopping, date: "2026-10-12") # Nov invoice
    entry("TV", 1200, on: { credit_card_id: card_id }, category: shopping, date: "2026-10-01", installments: 3)

    pay_invoice(card_id, "2026-10", account_id: nubank, date: "2026-10-10")
  end

  it "shows each account's balance from what was actually paid" do
    # 1000 + 5000 salary - 1500 rent - 100 transfer - 800 October invoice;
    # the scheduled 300 has not left the account yet.
    expect(balance_of(nubank)).to eq(3600)
    expect(balance_of(wallet)).to eq(300)
  end

  it "adds the counted accounts into Saldo geral" do
    expect(money(dashboard("2026-10")["consolidated_balance"])).to eq(3900)
  end

  it "counts card spending in the month its invoice is due, never the invoice payment or transfers" do
    october = dashboard("2026-10")["totals"]
    expect([money(october["income"]), money(october["expense"])]).to eq([5000, 2300]) # rent + 400 + 1st parcel

    november = dashboard("2026-11")["totals"]
    expect(money(november["expense"])).to eq(650) # 250 bought after the closing + 2nd parcel

    expect(money(dashboard("2026-12")["totals"]["expense"])).to eq(400) # 3rd parcel
  end

  it "keeps an entry still scheduled out of the month's totals, in the forecast (Rialign)" do
    expect(money(dashboard("2026-10")["forecast"]["expense"])).to eq(300)
  end

  it "shows the open invoice and the limit every unpaid parcel still holds" do
    summary = card_summary(card_id)

    expect(summary["current_invoice_month"]).to eq("2026-11")
    expect(money(summary["open_invoice"])).to eq(650)
    expect(money(summary["next_invoice"])).to eq(400)
    expect(money(summary["available_limit"])).to eq(3950) # 5000 - 650 - 400
  end

  it "leaves out of Saldo geral an account excluded from it, an archived one and one in dollars" do
    savings = account("Investimento", initial_balance: 5000, exclude_from_total: true)
    old = account("Conta antiga", initial_balance: 300)
    api(:delete, "/accounts/#{old}", expect: :no_content)
    dollars = account("Global", initial_balance: 100, currency: "USD")

    data = dashboard("2026-10")
    listed = data["accounts"].index_by { |a| a["id"] }

    expect(money(data["consolidated_balance"])).to eq(3900)
    expect(listed.keys).not_to include(old)
    expect(listed[savings]).to include("counted" => false, "current_balance" => "5000.0")
    # Organizze has no currencies and adds US$ 100 as R$ 100; Rialign keeps it out.
    expect(listed[dollars]).to include("counted" => false, "currency" => "USD")
  end

  # Organizze's "Maiores gastos" goes by purchase date, unlike Despesa mensal:
  # the Livro bought on 12/10 counts in October though it is on November's
  # invoice, and the TV counts by its first parcel only.
  it "breaks the month's spending down by category, by purchase date" do
    rows = dashboard("2026-10")["by_category"].to_h { |r| [r["name"], money(r["total"])] }
    # Casa includes the scheduled 300 (Rialign: the breakdown shows what is committed).
    expect(rows).to eq("Casa" => 1800, "Compras" => 1050) # 400 + 250 + 1st parcel

    expect(dashboard("2026-11")["by_category"]).to be_empty # only the TV's 2nd parcel
  end
end
