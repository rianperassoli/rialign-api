require "rails_helper"

RSpec.describe Imports::OrganizzeImport do
  let(:user) { create(:user) }
  let(:open_from) { Date.new(2026, 9, 1) }

  # The real export is a legacy BIFF .xls with one worksheet per source, so the
  # fixture is built in the same format rather than committed as a binary.
  def workbook(sheets)
    book = Spreadsheet::Workbook.new
    sheets.each do |name, rows|
      sheet = book.create_worksheet(name: name)
      sheet.row(0).push("Data", "Descrição", "Categoria", "Valor", "Situação", "Tags", "Informações adicionais")
      rows.each_with_index { |row, i| sheet.row(i + 1).concat(row) }
    end
    file = Tempfile.new(["export", ".xls"])
    book.write(file.path)
    file.path
  end

  def import(sheets, **opts)
    described_class.call(user:, path: workbook(sheets), open_from:, **opts)
  end

  it "reports a missing file instead of raising" do
    result = described_class.call(user:, path: "/nowhere/export.xls")
    expect(result).to be_failure
  end

  describe "sources" do
    it "creates an account per plain sheet and a credit card per '- Cartão' sheet" do
      import({ "NuBank" => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]],
               "NuBank - Cartão" => [["01.08.2026", "Livro", "Compras", -30.0, "Setembro/2026"]] })

      expect(user.accounts.pluck(:name)).to eq(["NuBank"])
      expect(user.credit_cards.pluck(:name)).to eq(["NuBank - Cartão"])
    end
  end

  describe "amounts" do
    it "stores the sign as kind and the value as a positive amount" do
      import({ "NuBank" => [["01.08.2026", "Salário", "Salário", 3000.0, "Pago"],
                            ["02.08.2026", "Mercado", "Mercado", -50.0, "Pago"]] })

      expect(user.transactions.income.pick(:amount)).to eq(3000)
      expect(user.transactions.expense.pick(:amount)).to eq(50)
    end

    it "skips rows the model cannot represent and counts them" do
      result = import({ "NuBank" => [["01.08.2026", "Ajuste", "Outros", 0.0, "Pago"]] })

      expect(result.data).to include(skipped_zero: 1)
      expect(user.transactions).to be_empty
    end

    it "keeps a positive card row as a credit on the invoice the file names" do
      result = import({ "NuBank - Cartão" => [["01.08.2026", "Estorno", "Outras receitas", 84.39, "Julho/2026"]] })

      credit = user.transactions.sole
      expect(result.data).to include(card_credits: 1, imported: 1)
      expect(credit).to have_attributes(kind: "income", amount: 84.39, invoice_month: Date.new(2026, 7, 1))
      expect(credit.credit_card.name).to eq("NuBank - Cartão")
      expect(credit.category).to have_attributes(name: "Outras receitas", kind: "income")
    end
  end

  # An export whose period reaches into the future also lists each open
  # invoice as a row of its own, on the card and on the paying account.
  describe "a period that reaches into the future" do
    let(:sheets) do
      { "NuBank" => [["01.10.2026", "Mercado", "Mercado", -50.0, "Pago"],
                     ["10.11.2026", "Fatura Novembro 2026", nil, -143.67, "Não pago"],
                     ["15.11.2026", "Aluguel", "Casa", -900.0, "Não pago"]],
        "NuBank - Cartão" => [["22.10.2026", "Cameras 7/12", "Compras", -143.67, "Novembro/2026"],
                              ["10.11.2026", "Fatura Novembro 2026", nil, -143.67, "Novembro/2026"]] }
    end

    it "skips the invoice rows, so an invoice is not counted twice" do
      result = import(sheets)

      expect(result.data).to include(skipped_invoice_bills: 2)
      expect(user.credit_cards.sole.transactions.sum(:amount)).to eq(143.67)
      expect(user.transactions.pluck(:description)).not_to include("Fatura Novembro 2026")
    end

    it "keeps an account entry still to be paid pending, out of the balance" do
      import(sheets)

      expect(user.transactions.find_by(description: "Aluguel").paid).to be(false)
      expect(Accounts::BalanceCalculator.new(user:).account_balance(user.accounts.sole)).to eq(-50)
    end
  end

  describe "settlement" do
    it "settles account rows" do
      import({ "NuBank" => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]] })
      expect(user.transactions.sole).to be_paid
    end

    # Situação on a card row is the invoice the charge belongs to, in Organizze's
    # due-month labelling: anything before open_from has already been paid.
    it "settles card charges from invoices older than open_from" do
      import({ "NuBank - Cartão" => [["01.07.2026", "Antiga", "Compras", -30.0, "Agosto/2026"],
                                     ["01.08.2026", "Atual", "Compras", -40.0, "Setembro/2026"],
                                     ["01.09.2026", "Futura", "Compras", -50.0, "Outubro/2026"]] })

      expect(user.transactions.paid.pluck(:description)).to eq(["Antiga"])
      expect(user.transactions.pending.pluck(:description)).to contain_exactly("Atual", "Futura")
    end

    # The export lists an invoice itself only while it is unpaid, so the oldest
    # one listed wins over open_from — card by card.
    it "settles everything before the oldest invoice the card's sheet still lists" do
      import({ "NuBank - Cartão" => [["01.08.2026", "Atual", "Compras", -40.0, "Setembro/2026"],
                                     ["01.09.2026", "Aberta", "Compras", -50.0, "Outubro/2026"],
                                     ["04.10.2026", "Fatura Outubro 2026", nil, -50.0, "Outubro/2026"]],
               "Outro - Cartão" => [["01.08.2026", "Sem lista", "Compras", -20.0, "Setembro/2026"]] })

      expect(user.transactions.paid.pluck(:description)).to eq(["Atual"])
      expect(user.transactions.pending.pluck(:description)).to contain_exactly("Aberta", "Sem lista")
    end

    it "settles a card row already marked Pago" do
      import({ "NuBank - Cartão" => [["01.08.2026", "Quitada", "Compras", -40.0, "Pago"]] })
      expect(user.transactions.sole).to be_paid
    end

    it "keeps a charge pending when the invoice month is unreadable" do
      import({ "NuBank - Cartão" => [["01.08.2026", "Sem fatura", "Compras", -40.0, ""]] })
      expect(user.transactions.sole).not_to be_paid
    end

    # A charge pushed to a later invoice in Organizze must stay there, not be
    # pulled back to the invoice its date would give.
    it "keeps the invoice named in the file" do
      import({ "NuBank - Cartão" => [["30.09.2026", "Adiada", "Compras", -35.0, "Novembro/2026"]] })
      expect(user.transactions.sole.invoice_month).to eq(Date.new(2026, 11, 1))
    end

    it "falls back to the date's invoice when the file names none" do
      import({ "NuBank - Cartão" => [["30.09.2026", "Quitada", "Compras", -35.0, "Pago"]] })
      expect(user.transactions.sole.invoice_month).to eq(Date.new(2026, 10, 1))
    end
  end

  # Organizze lists each parcel as its own row, the parcel at the end of the
  # description; newest first, as the export does.
  describe "installments" do
    let(:parcels) do
      [["22.10.2026", "Cameras 3/3", "Casa", -100.0, "Novembro/2026"],
       ["22.09.2026", "Cameras 2/3", "Casa", -100.0, "Outubro/2026"],
       ["22.08.2026", "Cameras 1/3", "Casa", -100.0, "Setembro/2026"]]
    end

    it "moves the parcel into the installment fields, one series per purchase" do
      import({ "NuBank - Cartão" => parcels })

      rows = user.transactions.order(:date).pluck(:description, :installment_number, :installment_total)
      expect(rows).to eq([["Cameras", 1, 3], ["Cameras", 2, 3], ["Cameras", 3, 3]])
      expect(user.transactions.distinct.count(:series_id)).to eq(1)
    end

    it "keeps two purchases of the same thing apart" do
      again = [["22.09.2026", "Cameras 1/3", "Casa", -100.0, "Outubro/2026"],
               ["22.10.2026", "Cameras 2/3", "Casa", -100.0, "Novembro/2026"]]
      import({ "NuBank - Cartão" => parcels + again })

      series = user.transactions.order(:date, :installment_number).group_by(&:series_id).values
      expect(series.map { |s| s.map(&:installment_number) }).to contain_exactly([1, 2, 3], [1, 2])
    end

    it "starts a series mid-way when the export period starts after the purchase" do
      import({ "NuBank - Cartão" => parcels.first(2) })
      expect(user.transactions.order(:date).pluck(:installment_number)).to eq([2, 3])
    end

    it "leaves account rows, credits, invoice payments and dates in a description alone" do
      import({ "NuBank" => [["01.10.2026", "Tv pai 7/12", "Outras receitas", 300.0, "Pago"]],
               "NuBank - Cartão" => [["01.10.2026", "Estorno 1/2", "Outras receitas", 50.0, "Novembro/2026"],
                                     ["01.10.2026", "Pagamento 1/2", "Pagamento de fatura", -20.0, "Novembro/2026"],
                                     ["sem data", "Cameras 1/3", "Casa", -100.0, "Novembro/2026"],
                                     ["02.10.2026", "Rendimento 08/2026", "Outros", -10.0, "Novembro/2026"]] })

      expect(user.transactions.pluck(:installment_number).uniq).to eq([nil])
      expect(user.transactions.pluck(:description)).to contain_exactly("Tv pai 7/12", "Estorno 1/2", "Pagamento 1/2",
                                                                       "Rendimento 08/2026")
    end
  end

  describe "categories" do
    it "creates one category per name and kind" do
      import({ "NuBank" => [["01.08.2026", "Venda", "Compras", 10.0, "Pago"],
                            ["02.08.2026", "Livro", "Compras", -30.0, "Pago"]] })

      expect(user.categories.pluck(:name, :kind)).to contain_exactly(%w[Compras income], %w[Compras expense])
    end

    it "dresses Organizze's own categories with their icon and colour" do
      import({ "NuBank" => [["01.08.2026", "Feira", "Mercado", -10.0, "Pago"],
                            ["02.08.2026", "Moto", "Ranger", -20.0, "Pago"]] })

      expect(user.categories.find_by(name: "Mercado")).to have_attributes(icon: "shopping-cart", color: "#ff7043")
      expect(user.categories.find_by(name: "Ranger")).to have_attributes(icon: nil, color: nil)
    end

    it "reuses a category across rows, ignoring surrounding whitespace" do
      import({ "NuBank" => [["01.08.2026", "A", "Investimentos", -10.0, "Pago"],
                            ["02.08.2026", "B", "Investimentos ", -20.0, "Pago"]] })

      expect(user.categories.count).to eq(1)
    end
  end

  describe "money movements" do
    # Transfer legs move the balance but are not spending, so they carry a
    # transfer_id and no category. A lone side stays unpaired.
    it "imports transfers and invoice payments as transfer legs" do
      import({ "NuBank" => [["01.08.2026", "Envio", "Transferências", -100.0, "Pago"],
                            ["02.08.2026", "Fatura", "Pagamento de fatura", -200.0, "Pago"]] })

      expect(user.transactions.count).to eq(2)
      expect(user.transactions.all?(&:transfer?)).to be(true)
      expect(user.transactions.pluck(:category_id).compact).to be_empty
      expect(user.transactions.pluck(:transfer_id).uniq.size).to eq(2)
    end

    it "pairs the two sides of a transfer across sheets by date and amount" do
      result = import({ "NuBank" => [["01.08.2026", "Envio", "Transferências", -100.0, "Pago"],
                                     ["01.08.2026", "Envio", "Transferências", -100.0, "Pago"],
                                     ["05.08.2026", "Envio", "Transferências", -30.0, "Pago"]],
                        "Carteira" => [["01.08.2026", "Recebido", "Transferências", 100.0, "Pago"],
                                       ["01.08.2026", "Recebido", "Transferências", 100.0, "Pago"],
                                       ["05.08.2026", "Recebido", "Transferências", 31.0, "Pago"]] })

      expect(result.data).to include(transfers_paired: 2, transfers_unpaired: 2)
      pairs = user.transactions.group(:transfer_id).count.values
      expect(pairs.sort).to eq([1, 1, 2, 2])
      user.transactions.where(amount: 100).group_by(&:transfer_id).each_value do |legs|
        expect(legs.map { |leg| leg.account.name }).to contain_exactly("NuBank", "Carteira")
      end
    end

    it "never pairs two sides on the same account" do
      result = import({ "NuBank" => [["01.08.2026", "Ida", "Transferências", -100.0, "Pago"],
                                     ["01.08.2026", "Volta", "Transferências", 100.0, "Pago"]] })
      expect(result.data).to include(transfers_paired: 0, transfers_unpaired: 2)
    end

    it "leaves invoice payments unpaired" do
      result = import({ "NuBank" => [["01.08.2026", "Fatura", "Pagamento de fatura", -100.0, "Pago"]],
                        "Carteira" => [["01.08.2026", "Recebido", "Transferências", 100.0, "Pago"]] })
      expect(result.data).to include(transfers_paired: 0, transfers_unpaired: 1)
    end
  end

  # The export names neither the card nor the invoice a payment paid; it is
  # matched by amount near the due date (the 10th, the default due day).
  describe "invoice payments" do
    let(:charges) do
      [["20.06.2026", "Mercado", "Mercado", -300.0, "Julho/2026"],
       ["20.07.2026", "Livro", "Compras", -500.0, "Agosto/2026"]]
    end

    def payment(date, amount, sheet: "NuBank")
      user.transactions.joins(:account).find_by!(accounts: { name: sheet }, date: Date.parse(date), amount:)
    end

    def invoice(month)
      CreditCardInvoiceQuery.new(user.credit_cards.sole, month:).call
    end

    it "links a payment to the invoice it matches, as a payment made in Rialign" do
      result = import({ "NuBank - Cartão" => charges,
                        "NuBank" => [["08.07.2026", "Pagamento de fatura", "Pagamento de fatura", -300.0, "Pago"],
                                     ["10.08.2026", "Pagamento de fatura", "Pagamento de fatura", -500.0, "Pago"]] })

      expect(result.data).to include(invoice_payments_linked: 2, invoice_payments_unlinked: 0)
      expect(invoice(Date.new(2026, 7, 1))[:payments]).to eq([payment("08.07.2026", 300)])
      expect(invoice(Date.new(2026, 8, 1))[:payments]).to eq([payment("10.08.2026", 500)])
    end

    it "makes one payment of an invoice paid in two goes" do
      import({ "NuBank - Cartão" => charges.first(1),
               "NuBank" => [["05.07.2026", "Antecipado", "Pagamento de fatura", -100.0, "Pago"],
                            ["09.07.2026", "Resto", "Pagamento de fatura", -200.0, "Pago"]] })

      legs = [payment("05.07.2026", 100), payment("09.07.2026", 200)]
      expect(invoice(Date.new(2026, 7, 1))[:payments]).to eq(legs)
      expect(legs.map(&:transfer_id).uniq.size).to eq(1)
    end

    # In Organizze a charge can sit on an invoice other than the one it was
    # paid with, so neither payment matches its invoice to the cent.
    it "falls back to the invoice due closest when no amount matches" do
      result = import({ "NuBank - Cartão" => charges,
                        "NuBank" => [["08.07.2026", "Pagamento de fatura", "Pagamento de fatura", -250.0, "Pago"],
                                     ["10.08.2026", "Pagamento de fatura", "Pagamento de fatura", -550.0, "Pago"]] })

      expect(result.data).to include(invoice_payments_linked: 2)
      expect(invoice(Date.new(2026, 7, 1))[:payments]).to eq([payment("08.07.2026", 250)])
      expect(invoice(Date.new(2026, 8, 1))[:payments]).to eq([payment("10.08.2026", 550)])
    end

    it "leaves alone a payment with no invoice in reach, and an invoice still open" do
      result = import({ "NuBank - Cartão" => [["20.08.2026", "Livro", "Compras", -80.0, "Setembro/2026"],
                                              ["20.08.2026", "Ajuste", "Pagamento de fatura", -5.0, "Setembro/2026"]],
                        "NuBank" => [["01.03.2026", "Antiga", "Pagamento de fatura", -50.0, "Pago"],
                                     ["10.09.2026", "Adiantado", "Pagamento de fatura", -80.0, "Pago"],
                                     ["11.09.2026", "Devolvido", "Pagamento de fatura", 80.0, "Pago"]] })

      expect(result.data).to include(invoice_payments_linked: 0, invoice_payments_unlinked: 2)
      expect(user.transactions.where.not(settled_by_id: nil)).to be_empty
    end
  end

  describe "dates" do
    it "skips a row whose date cannot be read" do
      result = import({ "NuBank" => [["not a date", "Mercado", "Mercado", -10.0, "Pago"]] })

      expect(result.data).to include(skipped_no_date: 1)
      expect(user.transactions).to be_empty
    end

    # Excel stores some cells as real dates rather than dd.mm.yyyy strings.
    it "accepts a date cell that is already a date" do
      import({ "NuBank" => [[Date.new(2026, 8, 1), "Mercado", "Mercado", -10.0, "Pago"]] })
      expect(user.transactions.pick(:date)).to eq(Date.new(2026, 8, 1))
    end
  end

  it "replaces open-ended fixed entries along with everything else" do
    Recurrences::Start.call(user:, params: { description: "Aluguel", kind: "expense", amount: 1000,
                                             date: Date.current, account_id: create(:account, user:).id,
                                             category_id: create(:category, user:).id })

    import({ "NuBank" => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]] }, replace_existing: true)
    expect(user.recurrences.reload).to be_empty
    expect(user.transactions.reload.pluck(:description)).to eq(["Mercado"])
  end

  # The wipe and the write share one transaction, so a row that cannot be saved
  # takes the deletion down with it. A failed import must never leave the user
  # with less than they started with.
  describe "when a row cannot be saved" do
    let(:sheets) do
      { "NuBank" => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]],
        " " => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]] }
    end

    it "reports the failure instead of raising" do
      result = import(sheets, replace_existing: true)

      expect(result).to be_failure
      expect(result.errors.first).to match(/Name can't be blank/)
    end

    it "leaves the data the user already had untouched" do
      account = create(:account, user:, name: "Antiga")
      create(:transaction, user:, account:, description: "Antiga compra")

      import(sheets, replace_existing: true)

      expect(user.accounts.reload.pluck(:name)).to eq(["Antiga"])
      expect(user.transactions.reload.pluck(:description)).to eq(["Antiga compra"])
    end

    it "writes nothing from the rows it had already read" do
      import(sheets, replace_existing: true)

      expect(user.accounts.reload).to be_empty
      expect(user.transactions.reload).to be_empty
      expect(user.categories.reload).to be_empty
    end
  end

  it "falls back to a placeholder when the description is blank" do
    import({ "NuBank" => [["01.08.2026", nil, "Outros", -10.0, "Pago"]] })
    expect(user.transactions.pick(:description)).to eq("(sem descrição)")
  end

  it "carries 'Informações adicionais' into notes" do
    import({ "NuBank" => [["01.08.2026", "Mercado", "Mercado", -10.0, "Pago", nil, "obs"]] })
    expect(user.transactions.pick(:notes)).to eq("obs")
  end

  it "applies the given defaults over the fallback closing and due days" do
    import({ "MP - Cartão" => [["01.08.2026", "Livro", "Compras", -30.0, "Setembro/2026"]] },
           defaults: { credit_cards: { "MP - Cartão" => { due_day: 4 } } })

    expect(user.credit_cards.sole).to have_attributes(due_day: 4, closing_day: 31)
  end

  describe "opening balance" do
    let(:rows) do
      { "NuBank" => [["01.08.2026", "Salário", "Salário", 3000.0, "Pago"],
                     ["02.08.2026", "Mercado", "Mercado", -500.0, "Pago"],
                     ["03.08.2026", "Pix", "Transferências", -100.0, "Pago"]] }
    end

    def balance
      Accounts::BalanceCalculator.new(user:).account_balance(user.accounts.sole)
    end

    it "works it out from the balance Organizze shows today" do
      import(rows, defaults: { accounts: { "NuBank" => { "current_balance" => "2650.55" } } })

      expect(user.accounts.sole.initial_balance).to eq(250.55)
      expect(balance).to eq(2650.55)
    end

    it "books every account in reais, as Organizze has no currencies" do
      import(rows, defaults: { accounts: { "NuBank" => { "currency" => "USD" } } })
      expect(user.accounts.sole).to have_attributes(currency: "BRL", counted?: true)
    end

    it "starts at zero when no balance is given" do
      import(rows, defaults: { accounts: { "NuBank" => { "exclude_from_total" => true } } })

      expect(user.accounts.sole).to have_attributes(initial_balance: 0, exclude_from_total: true)
      expect(balance).to eq(2400)
    end
  end
end
