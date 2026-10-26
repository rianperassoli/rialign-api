require "rails_helper"

RSpec.describe Imports::AnalyzeOrganizzeExport do
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

  def analyze(sheets)
    described_class.call(path: workbook(sheets)).data
  end

  # The invoice a charge made in `month` lands on, named the way the export
  # names it: after the month it is due.
  def invoice_after(year, month)
    meses = %w[Janeiro Fevereiro Março Abril Maio Junho
               Julho Agosto Setembro Outubro Novembro Dezembro]
    due = Date.new(year, month, 1) >> 1
    "#{meses[due.month - 1]}/#{due.year}"
  end

  # Charges on consecutive invoices, closing on the last day of each month.
  def month_end_card(months)
    months.flat_map do |year, month, invoice|
      last = Date.new(year, month, -1)
      [["#{last.day}.#{format("%02d", month)}.#{year}", "Compra", "Compras", -10.0, invoice],
       ["01.#{format("%02d", month)}.#{year}", "Compra", "Compras", -10.0, invoice]]
    end
  end

  it "reports a failure when the file is missing" do
    expect(described_class.call(path: "/nowhere/export.xls")).to be_failure
  end

  it "separates accounts from cards and counts their rows" do
    result = analyze({ "NuBank" => [["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]],
                       "NuBank - Cartão" => [["01.08.2026", "Livro", "Compras", -30.0, "Setembro/2026"]] })

    expect(result[:accounts]).to eq([{ name: "NuBank", rows: 1, balance: "-50.0", currency: "BRL" }])
    expect(result[:credit_cards].sole).to include(name: "NuBank - Cartão", rows: 1)
  end

  it "lists the invoices found on a card" do
    result = analyze({ "NuBank - Cartão" => month_end_card([[2026, 6, invoice_after(2026, 6)],
                                                            [2026, 7, invoice_after(2026, 7)]]) })

    expect(result[:credit_cards].sole[:invoice_months]).to eq(%w[2026-07 2026-08])
  end

  describe "closing day" do
    # It is never written down, only bounded: the last charge of one invoice and
    # the first of the next straddle it.
    it "reads month-end closing from where invoices split" do
      result = analyze({ "NuBank - Cartão" => month_end_card([[2026, 5, invoice_after(2026, 5)],
                                                              [2026, 6, invoice_after(2026, 6)],
                                                              [2026, 7, invoice_after(2026, 7)]]) })

      expect(result[:credit_cards].sole[:closing_day]).to eq(31)
    end

    it "reads a mid-month closing" do
      rows = [["10.06.2026", "A", "Compras", -10.0, "Julho/2026"],
              ["20.06.2026", "B", "Compras", -10.0, "Agosto/2026"],
              ["10.07.2026", "C", "Compras", -10.0, "Agosto/2026"],
              ["20.07.2026", "D", "Compras", -10.0, "Setembro/2026"]]

      expect(analyze({ "NuBank - Cartão" => rows })[:credit_cards].sole[:closing_day]).to be_between(10, 19)
    end

    it "falls back to month-end when a single invoice gives nothing to compare" do
      rows = [["10.06.2026", "A", "Compras", -10.0, "Julho/2026"]]

      expect(analyze({ "NuBank - Cartão" => rows })[:credit_cards].sole[:closing_day]).to eq(31)
    end

    # A card's closing day changes over the years; only current behaviour counts.
    it "ignores invoices older than the recent window" do
      # Two years closing mid-month, then a year closing at month end. The old
      # behaviour outnumbers the new one, and must still lose.
      old = (1..24).map do |i|
        month = Date.new(2023, 1, 1) >> i
        [month.change(day: 10).strftime("%d.%m.%Y"), "antiga", "Compras", -10.0, invoice_after(month.year, month.month)]
      end
      old += (1..24).map do |i|
        month = Date.new(2023, 1, 1) >> i
        [month.change(day: 20).strftime("%d.%m.%Y"), "antiga", "Compras", -10.0,
         invoice_after((month >> 1).year, (month >> 1).month)]
      end
      recent = month_end_card((1..12).map { |m| [2026, m, invoice_after(2026, m)] })

      expect(analyze({ "NuBank - Cartão" => old + recent })[:credit_cards].sole[:closing_day]).to eq(31)
    end
  end

  it "sums an account's rows into the balance the file alone gives, without float drift" do
    result = analyze({ "NuBank" => [["01.08.2026", "Salário", "Salário", 0.1, "Pago"],
                                    ["02.08.2026", "Pix", "Outros", 0.2, "Pago"],
                                    ["03.08.2026", "Mercado", "Mercado", -10.05, "Pago"]] })

    expect(result[:accounts].sole[:balance]).to eq("-9.75")
  end

  it "guesses the currency an account is named after" do
    names = ["Carteira USD", "NuBank - GLOBAL USD", "Nubank (USD)", "Conta Euro", "Libra UK", "Usdinheiro"]
    accounts = analyze(names.index_with { [] })[:accounts]

    expect(accounts.pluck(:currency)).to eq(%w[USD USD USD EUR GBP BRL])
  end

  it "leaves projected invoices and entries still to be paid out of the balance and the closing day" do
    result = analyze({ "NuBank" => [["01.10.2026", "Mercado", "Mercado", -50.0, "Pago"],
                                    ["10.11.2026", "Fatura Novembro 2026", nil, -100.0, "Não pago"],
                                    ["15.11.2026", "Aluguel", "Casa", -900.0, "Não pago"]],
                       "MP - Cartão" => [["20.09.2026", "Livro", "Compras", -30.0, "Outubro/2026"],
                                         ["28.09.2026", "Café", "Compras", -10.0, "Novembro/2026"],
                                         ["04.10.2026", "Fatura Outubro 2026", nil, -30.0, "Outubro/2026"]] })

    expect(result[:accounts].sole[:balance]).to eq("-50.0")
    expect(result[:credit_cards].sole[:closing_day]).to eq(27)
  end

  it "reports a sheet that has only a header" do
    expect(analyze({ "Vazia" => [] })[:accounts]).to eq([{ name: "Vazia", rows: 0, balance: "0.0", currency: "BRL" }])
  end

  it "skips a sheet with not even a header" do
    book = Spreadsheet::Workbook.new
    book.create_worksheet(name: "Nada")
    file = Tempfile.new(["export", ".xls"])
    book.write(file.path)

    expect(described_class.call(path: file.path).data[:accounts]).to be_empty
  end

  it "ignores card rows it cannot place on an invoice" do
    rows = [["01.06.2026", "sem fatura", "Compras", -10.0, ""],
            ["nao e data", "sem data", "Compras", -10.0, "Julho/2026"]]

    expect(analyze({ "NuBank - Cartão" => rows })[:credit_cards].sole)
      .to include(rows: 2, invoice_months: [], closing_day: 31)
  end

  # Two charges on the same day landing on different invoices leaves no room
  # between them, so that boundary says nothing and must be dropped.
  it "ignores a boundary with no room between invoices" do
    rows = [["30.06.2026", "A", "Compras", -10.0, "Julho/2026"],
            ["30.06.2026", "B", "Compras", -10.0, "Agosto/2026"],
            ["31.07.2026", "C", "Compras", -10.0, "Agosto/2026"],
            ["01.08.2026", "D", "Compras", -10.0, "Setembro/2026"]]

    expect(analyze({ "NuBank - Cartão" => rows })[:credit_cards].sole[:closing_day]).to eq(31)
  end
end
