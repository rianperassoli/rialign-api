require "rails_helper"

# A credit card used for a few months, built through the API, against what
# Organizze shows on the card and its invoices: which invoice a purchase lands
# on, invoice totals and status, refunds, installments, the available limit,
# and paying an invoice in full, in part, or undoing the payment.
RSpec.describe "Organizze parity: credit card", type: :request do
  include OrganizzeScenario

  let(:user) { create(:user) }
  let(:nubank) { account("NuBank", initial_balance: 10_000) }
  let(:shopping) { category("Compras") }
  let(:refunds) { category("Estornos", kind: "income") }
  # Closes on the 3rd, due on the 10th of the same month.
  let(:card_id) { card("NuBank - Cartão", limit: 3000, closing_day: 3, due_day: 10, payment_account: nubank) }

  before { travel_to Date.new(2026, 10, 15) }

  def buy(description, amount, date, **)
    entry(description, amount, on: { credit_card_id: card_id }, category: shopping, date:, **)
  end

  describe "which invoice a purchase lands on" do
    it "goes on that month's invoice up to the closing day and on the next one after it" do
      buy("No fechamento", 100, "2026-10-03")
      buy("Depois do fechamento", 50, "2026-10-04")

      october = invoice(card_id, "2026-10")
      expect(october["transactions"].pluck("description")).to eq(["No fechamento"])
      expect(october).to include("closing_date" => "2026-10-03", "due_date" => "2026-10-10",
                                 "period" => { "from" => "2026-09-04", "to" => "2026-10-03" })
      expect(invoice(card_id, "2026-11")["transactions"].pluck("description")).to eq(["Depois do fechamento"])
    end

    it "names the invoice after the month it is due when the card closes at month end" do
      month_end = card("Fecha no fim do mês", limit: 1000, closing_day: 31, due_day: 10)
      entry("Compra", 80, on: { credit_card_id: month_end }, category: shopping, date: "2026-10-15")

      expect(money(invoice(month_end, "2026-11")["total"])).to eq(80)
    end

    it "reads closed once past the closing day while unpaid, and open while still taking purchases" do
      buy("Outubro", 100, "2026-10-02")
      buy("Novembro", 100, "2026-10-12")

      expect(invoice(card_id, "2026-10")["status"]).to eq("closed")
      expect(invoice(card_id, "2026-11")["status"]).to eq("open")
      expect(card_summary(card_id)["current_invoice_month"]).to eq("2026-11")
    end
  end

  describe "refunds" do
    it "lowers the invoice the refund sits on and gives the limit back" do
      buy("Tênis", 500, "2026-10-12")
      income("Estorno tênis", 120, on: { credit_card_id: card_id }, category: refunds, date: "2026-10-14")

      november = invoice(card_id, "2026-11")
      expect(money(november["total"])).to eq(380)
      expect(november["transactions"].map { |t| money(t["signed_amount"]) }).to contain_exactly(-500, 120)
      expect(money(card_summary(card_id)["available_limit"])).to eq(2620)
    end
  end

  describe "installments" do
    it "puts one parcel on each invoice, holds the whole purchase on the limit and frees a parcel when paid" do
      buy("Geladeira", 900, "2026-10-12", installments: 3)

      expect(%w[2026-11 2026-12 2027-01].map { |m| money(invoice(card_id, m)["total"]) }).to eq([300, 300, 300])
      expect(money(card_summary(card_id)["available_limit"])).to eq(2100)

      pay_invoice(card_id, "2026-11", account_id: nubank, date: "2026-11-10")
      expect(money(card_summary(card_id)["available_limit"])).to eq(2400)
    end

    it "puts the cent left over by the split on the first parcel" do
      buy("Fone", 100, "2026-10-12", installments: 3)
      expect(%w[2026-11 2026-12 2027-01].map { |m| money(invoice(card_id, m)["total"]) }).to eq([33.34, 33.33, 33.33])
    end
  end

  describe "paying the invoice" do
    before do
      buy("Mercado", 700, "2026-10-12")
      buy("Farmácia", 300, "2026-10-13")
    end

    it "settles it in full from the account, once, without counting it as a second expense" do
      payment = pay_invoice(card_id, "2026-11", account_id: nubank, date: "2026-11-10")

      expect(money(payment["amount"])).to eq(1000)
      november = invoice(card_id, "2026-11")
      expect([november["status"], money(november["pending"])]).to eq(["paid", 0])
      expect(balance_of(nubank, month: "2026-11")).to eq(9000)
      expect(money(card_summary(card_id)["available_limit"])).to eq(3000)
      expect(money(dashboard("2026-11")["totals"]["expense"])).to eq(1000)
    end

    it "settles it in part and carries what was left to the next invoice" do
      buy("Dezembro", 50, "2026-11-20")
      pay_invoice(card_id, "2026-11", account_id: nubank, date: "2026-11-10", amount: 400)

      expect(invoice(card_id, "2026-11")["status"]).to eq("paid")
      december = invoice(card_id, "2026-12")
      expect(money(december["total"])).to eq(650) # 600 left over + 50 bought in November
      expect(balance_of(nubank, month: "2026-11")).to eq(9600)
      expect(money(card_summary(card_id)["available_limit"])).to eq(2350)
      # The 600 carried over was already counted as November spending.
      expect(money(dashboard("2026-12")["totals"]["expense"])).to eq(50)
    end

    it "is undone by deleting the payment: the invoice reopens and the money goes back" do
      payment = pay_invoice(card_id, "2026-11", account_id: nubank, date: "2026-11-10", amount: 400)
      api(:delete, "/transactions/#{payment["id"]}", expect: :no_content)

      november = invoice(card_id, "2026-11")
      # Still before its closing day (03/11), so it is open again.
      expect([november["status"], money(november["pending"]), november["payments"]]).to eq(["open", 1000, []])
      expect(money(invoice(card_id, "2026-12")["total"])).to eq(0)
      expect(balance_of(nubank, month: "2026-11")).to eq(10_000)
    end

    # Organizze has no "paid" on a purchase: the invoice is what gets paid.
    # Unsettling one charge of a paid invoice let it be paid a second time.
    it "settles a purchase only through its invoice, never by marking it by hand" do
      pay_invoice(card_id, "2026-11", account_id: nubank, date: "2026-11-10")
      market = transactions(search: "Mercado").sole

      api(:patch, "/transactions/#{market["id"]}", { transaction: { paid: false } }, expect: :unprocessable_entity)
      api(:patch, "/transactions/#{market["id"]}", { transaction: { description: "Mercado do mês", paid: true } },
          expect: :ok)

      expect(invoice(card_id, "2026-11")["status"]).to eq("paid")
      expect(balance_of(nubank, month: "2026-11")).to eq(9000)
    end

    it "needs to know which invoice is being paid" do
      api(:post, "/credit_cards/#{card_id}/pay_invoice", { payment: { account_id: nubank } },
          expect: :unprocessable_entity)
      expect(money(invoice(card_id, "2026-11")["pending"])).to eq(1000)
    end
  end

  describe "moving an entry between an account and the card" do
    let(:wallet) { account("Carteira", initial_balance: 500) }

    it "puts an account expense on the invoice, pending, and gives the money back to the account" do
      paid_in_cash = entry("Livro", 100, on: wallet, category: shopping, date: "2026-10-12")
      api(:patch, "/transactions/#{paid_in_cash["id"]}", { transaction: { account_id: nil, credit_card_id: card_id } },
          expect: :ok)

      expect(money(invoice(card_id, "2026-11")["pending"])).to eq(100)
      expect(money(card_summary(card_id)["available_limit"])).to eq(2900)
      expect(balance_of(wallet)).to eq(500)
    end

    it "takes a purchase off the invoice and out of the account it moves to" do
      purchase = buy("Livro", 100, "2026-10-12")
      api(:patch, "/transactions/#{purchase["id"]}",
          { transaction: { credit_card_id: nil, account_id: wallet, paid: true } }, expect: :ok)

      expect(money(invoice(card_id, "2026-11")["total"])).to eq(0)
      expect(balance_of(wallet)).to eq(400)
    end
  end

  describe "moving a purchase to another invoice" do
    it "moves it to the next invoice, but never onto one already paid" do
      early = buy("Antecipada", 100, "2026-10-02")
      late = buy("Adiada", 40, "2026-10-12")
      pay_invoice(card_id, "2026-10", account_id: nubank, date: "2026-10-10")

      api(:patch, "/transactions/#{late["id"]}", { transaction: { invoice_month: "2026-12" } }, expect: :ok)
      expect(invoice(card_id, "2026-12")["transactions"].pluck("description")).to eq(["Adiada"])

      api(:patch, "/transactions/#{late["id"]}", { transaction: { invoice_month: "2026-10" } },
          expect: :unprocessable_entity)
      expect(invoice(card_id, "2026-10")["transactions"].pluck("id")).to eq([early["id"]])
    end
  end

  # Rialign does not block a purchase above the limit; the available limit
  # goes negative, which is how the overspend shows.
  it "lets a purchase go over the limit and shows the overspend" do
    buy("Viagem", 3200, "2026-10-12")
    expect(money(card_summary(card_id)["available_limit"])).to eq(-200)
  end
end
