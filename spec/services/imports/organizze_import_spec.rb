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
      result = import({ "NuBank" => [["01.08.2026", "Ajuste", "Outros", 0.0, "Pago"]],
                        "NuBank - Cartão" => [["01.08.2026", "Estorno", "Outras receitas", 84.39, "Julho/2026"]] })

      expect(result.data).to include(skipped_zero: 1, skipped_card_credit: 1)
      expect(user.transactions).to be_empty
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

    it "settles a card row already marked Pago" do
      import({ "NuBank - Cartão" => [["01.08.2026", "Quitada", "Compras", -40.0, "Pago"]] })
      expect(user.transactions.sole).to be_paid
    end

    it "keeps a charge pending when the invoice month is unreadable" do
      import({ "NuBank - Cartão" => [["01.08.2026", "Sem fatura", "Compras", -40.0, ""]] })
      expect(user.transactions.sole).not_to be_paid
    end
  end

  describe "categories" do
    it "creates one category per name and kind" do
      import({ "NuBank" => [["01.08.2026", "Venda", "Compras", 10.0, "Pago"],
                            ["02.08.2026", "Livro", "Compras", -30.0, "Pago"]] })

      expect(user.categories.pluck(:name, :kind)).to contain_exactly(%w[Compras income], %w[Compras expense])
    end

    it "reuses a category across rows, ignoring surrounding whitespace" do
      import({ "NuBank" => [["01.08.2026", "A", "Investimentos", -10.0, "Pago"],
                            ["02.08.2026", "B", "Investimentos ", -20.0, "Pago"]] })

      expect(user.categories.count).to eq(1)
    end
  end

  describe "money movements" do
    # Transfer legs move the balance but are not spending, so they carry a
    # transfer_id and no category — the export never identifies the other leg.
    it "imports transfers and invoice payments as unpaired transfer legs" do
      import({ "NuBank" => [["01.08.2026", "Envio", "Transferências", -100.0, "Pago"],
                            ["02.08.2026", "Fatura", "Pagamento de fatura", -200.0, "Pago"]] })

      expect(user.transactions.count).to eq(2)
      expect(user.transactions.all?(&:transfer?)).to be(true)
      expect(user.transactions.pluck(:category_id).compact).to be_empty
      expect(user.transactions.pluck(:transfer_id).uniq.size).to eq(2)
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
end
