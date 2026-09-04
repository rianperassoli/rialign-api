require "rails_helper"

RSpec.describe OrganizzeImportJob, type: :job do
  let(:user) { create(:user) }

  def export(rows, sheet: "NuBank")
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: sheet)
    sheet.row(0).push("Data", "Descrição", "Categoria", "Valor", "Situação", "Tags", "Informações adicionais")
    rows.each_with_index { |row, i| sheet.row(i + 1).concat(row) }
    path = Rails.root.join("tmp/imports", Rails.env, "#{SecureRandom.uuid}.xls")
    FileUtils.mkdir_p(File.dirname(path))
    book.write(path)
    path.to_s
  end

  # The write pass only runs on an import the user already confirmed.
  def import_for(path, settings: {})
    create(:import, user:, file_path: path, status: "importing", settings:)
  end

  it "records the report and marks the import completed" do
    import = import_for(export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]]))

    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: "completed", error_message: nil)
    expect(import.report["imported"]).to eq(1)
    expect(user.transactions.count).to eq(1)
  end

  # The export is a full history, so a second run replaces rather than appends.
  it "replaces what the user already had" do
    old = create(:account, user:, name: "Antiga")
    import = import_for(export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]]))

    described_class.perform_now(import.id)

    expect(Account.unscoped.where(id: old.id)).to be_empty
    expect(user.accounts.pluck(:name)).to eq(["NuBank"])
  end

  it "deletes the uploaded file once it is done with it" do
    path = export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]])
    described_class.perform_now(import_for(path).id)

    expect(File).not_to exist(path)
  end

  # What the import screen promises the user when it says nothing was changed.
  it "leaves the user's data in place when the import fails" do
    account = create(:account, user:, name: "Antiga")
    book = Spreadsheet::Workbook.new
    ["NuBank", " "].each do |name|
      sheet = book.create_worksheet(name: name)
      sheet.row(0).push("Data", "Descrição", "Categoria", "Valor", "Situação", "Tags", "Informações adicionais")
      sheet.row(1).push("01.08.2026", "Mercado", "Mercado", -50.0, "Pago")
    end
    path = Rails.root.join("tmp/imports", Rails.env, "#{SecureRandom.uuid}.xls")
    FileUtils.mkdir_p(File.dirname(path))
    book.write(path)

    described_class.perform_now(import_for(path.to_s).id)

    expect(Import.last.status).to eq("failed")
    expect(user.accounts.reload.pluck(:name)).to eq([account.name])
  end

  it "records a failure instead of raising when the file is unreadable" do
    import = create(:import, user:, file_path: "/nowhere/missing.xls", status: "importing")

    expect { described_class.perform_now(import.id) }.not_to raise_error
    expect(import.reload).to have_attributes(status: "failed")
    expect(import.error_message).to match(/File not found/)
  end

  it "records a failure when the spreadsheet itself is malformed" do
    path = Rails.root.join("tmp/imports", Rails.env, "#{SecureRandom.uuid}.xls")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "not a spreadsheet")

    described_class.perform_now(import_for(path.to_s).id)

    expect(Import.last.status).to eq("failed")
  ensure
    FileUtils.rm_f(path)
  end

  it "ignores an import that is not waiting to be written" do
    import = create(:import, user:, status: "awaiting_input")

    expect { described_class.perform_now(import.id) }.not_to(change { import.reload.status })
  end

  it "applies the settings the user confirmed" do
    path = export([["01.08.2026", "Livro", "Compras", -30.0, "Setembro/2026"]], sheet: "NuBank - Cartão")
    import = import_for(path, settings: {
                          "open_from" => "2026-10",
                          "credit_cards" => { "NuBank - Cartão" => { "due_day" => 4, "credit_limit" => "900.0" } }
                        })

    described_class.perform_now(import.id)

    expect(user.credit_cards.sole).to have_attributes(due_day: 4, credit_limit: 900)
    # October is the first open invoice, so September's charge is already paid.
    expect(user.transactions.sole).to be_paid
  end

  it "marks an account as excluded from the total when asked" do
    path = export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]])
    import = import_for(path, settings: { "accounts" => { "NuBank" => { "exclude_from_total" => true } } })

    described_class.perform_now(import.id)

    expect(user.accounts.sole.exclude_from_total).to be(true)
  end

  it "falls back to the current month when open_from is unusable" do
    path = export([["01.08.2026", "Livro", "Compras", -30.0, "Setembro/2026"]], sheet: "NuBank - Cartão")
    import = import_for(path, settings: { "open_from" => "not a month" })

    travel_to Date.new(2026, 9, 15) do
      described_class.perform_now(import.id)
    end

    # September is open at that point, so the September invoice stays pending.
    expect(user.transactions.sole).not_to be_paid
  end

  it "ignores an import that no longer exists" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
