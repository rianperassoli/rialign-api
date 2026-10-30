require "rails_helper"

# A made-up Organizze export, shaped like the real one, imported through the
# API and its background jobs (upload -> analysis -> answers -> write), after
# which the dashboard must show what Organizze shows for the same data.
#
# The export holds: an account with salary, rent, a transfer out, two invoice
# payments, a scheduled bill and the projected invoice Organizze lists when the
# period reaches into the future; the account the transfer went to; a dollar
# account; and a card with a paid September invoice, a paid October one, an
# open November one with a refund, and the last parcel booked for December.
RSpec.describe "Organizze parity: import", type: :request do
  include OrganizzeScenario
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  # What the user answers in the wizard, read off Organizze's own screens.
  let(:answers) do
    {
      open_from: "2026-11",
      accounts: { "NuBank" => { current_balance: "3400.00" }, "Carteira USD" => { currency: "USD" } }, # ignored
      credit_cards: { "NuBank - Cartão" => { closing_day: 3, due_day: 10, credit_limit: "5000" } }
    }
  end
  let!(:import) do
    travel_to Date.new(2026, 10, 15)
    perform_enqueued_jobs do
      post "/api/v1/imports", params: { file: upload(export) }, headers: auth_headers(user).except("Content-Type")
    end
    id = json.dig("data", "id")
    perform_enqueued_jobs { api(:post, "/imports/#{id}/confirm", { settings: answers }, expect: :accepted) }
    api(:get, "/imports/#{id}", expect: :ok)["data"]
  end

  let(:export) do
    {
      "NuBank" => [
        ["05.10.2026", "Salário", "Salário", 5000.0, "Pago"],
        ["06.10.2026", "Aluguel", "Casa", -1500.0, "Pago"],
        ["07.10.2026", "Transferência para Carteira", "Transferências", -100.0, "Pago"],
        ["10.09.2026", "Fatura Setembro", "Pagamento de fatura", -200.0, "Pago"],
        ["10.10.2026", "Fatura Outubro", "Pagamento de fatura", -800.0, "Pago"],
        ["20.10.2026", "Luz", "Casa", -300.0, "Não pago"],
        ["10.11.2026", "Fatura Novembro 2026", nil, -600.0, "Não pago"]
      ],
      "Carteira" => [
        ["07.10.2026", "Transferência de NuBank", "Transferências", 100.0, "Pago"],
        ["08.10.2026", "Café", "Bares", -30.0, "Pago"]
      ],
      "Carteira USD" => [["01.10.2026", "Depósito", "Outras receitas", 50.0, "Pago"]],
      "NuBank - Cartão" => [
        ["01.09.2026", "Farmácia", "Saúde", -200.0, "Setembro/2026"],
        ["01.10.2026", "TV 1/3", "Compras", -400.0, "Outubro/2026"],
        ["02.10.2026", "Mercado", "Compras", -400.0, "Outubro/2026"],
        ["12.10.2026", "Livro", "Compras", -250.0, "Novembro/2026"],
        ["14.10.2026", "Estorno livro", "Outras receitas", 50.0, "Novembro/2026"],
        ["01.11.2026", "TV 2/3", "Compras", -400.0, "Novembro/2026"],
        ["01.12.2026", "TV 3/3", "Compras", -400.0, "Dezembro/2026"],
        ["10.11.2026", "Fatura Novembro 2026", nil, -600.0, "Novembro/2026"]
      ]
    }
  end

  # The real export is a legacy BIFF .xls with one worksheet per source.
  def upload(sheets)
    book = Spreadsheet::Workbook.new
    sheets.each do |name, rows|
      sheet = book.create_worksheet(name:)
      sheet.row(0).push("Data", "Descrição", "Categoria", "Valor", "Situação", "Tags", "Informações adicionais")
      rows.each_with_index { |row, i| sheet.row(i + 1).concat(row) }
    end
    file = Tempfile.new(["movimentacoes", ".xls"])
    book.write(file.path)
    Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel", original_filename: "movimentacoes.xls")
  end

  def account_id(name)
    dashboard("2026-10")["accounts"].find { |a| a["name"] == name }["id"]
  end

  def card_id
    card = dashboard("2026-10")["credit_cards"].sole
    card["id"]
  end

  it "finishes, reporting what it read" do
    expect(import["status"]).to eq("completed")
    expect(import["report"]).to include("accounts" => 3, "credit_cards" => 1, "card_credits" => 1,
                                        "skipped_invoice_bills" => 2, "transfers_paired" => 1,
                                        "transfers_unpaired" => 0)
  end

  it "pre-filled each account's balance from its paid rows" do
    preview = import["preview"]["accounts"].index_by { |a| a["name"] }

    expect(preview["NuBank"]).to include("balance" => "2400.0") # without opening balance
    expect(preview["Carteira"]).to include("balance" => "70.0")
  end

  it "ends each account on the balance Organizze shows, and adds them into Saldo geral" do
    data = dashboard("2026-10")

    expect(balance_of(account_id("NuBank"))).to eq(3400) # the balance typed in the wizard
    expect(balance_of(account_id("Carteira"))).to eq(70)
    expect(balance_of(account_id("Carteira USD"))).to eq(50)
    # Every account in reais, the dollar one too, as Organizze adds them up.
    expect(money(data["consolidated_balance"])).to eq(3520)
  end

  it "shows the open invoice once, with its refund, and the limit the unpaid parcels hold" do
    november = invoice(card_id, "2026-11")
    card = card_summary(card_id)

    expect([november["status"], money(november["total"])]).to eq(["open", 600]) # 250 + 400 - 50
    expect(money(invoice(card_id, "2026-10")["total"])).to eq(800)
    expect(invoice(card_id, "2026-10")["status"]).to eq("paid")
    expect([money(card["open_invoice"]), money(card["next_invoice"])]).to eq([600, 400])
    expect(money(card["available_limit"])).to eq(4000)
  end

  it "shows the month's income and expense the way Organizze does" do
    october = dashboard("2026-10")
    # Rent + coffee + the October invoice; transfers and invoice payments are
    # not spending, and the scheduled bill is still to be paid. The dollar
    # account's deposit is income in reais, as Organizze counts it.
    expect([money(october["totals"]["income"]), money(october["totals"]["expense"])]).to eq([5050, 2330])
    expect(money(october["forecast"]["expense"])).to eq(300)
    expect(money(dashboard("2026-11")["totals"]["expense"])).to eq(650)
  end

  it "joins the two sides of the transfer, so it is edited and deleted as one" do
    # The list also holds the imported invoice payments (one-sided, see the
    # "Pagamento de fatura" rows), so pick the transfer by its accounts.
    transfer = api(:get, "/transfers", expect: :ok)["data"].find { |t| t["to_account_id"] }

    expect(transfer).to include("from_account_id" => account_id("NuBank"), "to_account_id" => account_id("Carteira"))
    api(:delete, "/transfers/#{transfer["transfer_id"]}", expect: :no_content)
    expect(balance_of(account_id("Carteira"))).to eq(-30)
  end

  it "leaves the scheduled bill pending and drops the projected invoices" do
    bill = transactions(search: "Luz").sole

    expect(bill["paid"]).to be(false)
    expect(transactions(search: "Fatura Novembro")).to be_empty
  end
end
