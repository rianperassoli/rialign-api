require "rails_helper"

RSpec.describe AnalyzeImportJob, type: :job do
  let(:user) { create(:user) }

  def export(rows, sheet: "NuBank")
    book = Spreadsheet::Workbook.new
    worksheet = book.create_worksheet(name: sheet)
    worksheet.row(0).push("Data", "Descrição", "Categoria", "Valor", "Situação", "Tags", "Informações adicionais")
    rows.each_with_index { |row, i| worksheet.row(i + 1).concat(row) }
    path = Rails.root.join("tmp/imports", Rails.env, "#{SecureRandom.uuid}.xls")
    FileUtils.mkdir_p(File.dirname(path))
    book.write(path)
    path.to_s
  end

  after { FileUtils.rm_rf(Rails.root.join("tmp/imports", Rails.env)) }

  it "parks the import waiting for input, with what it found" do
    import = create(:import, user:, file_path: export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]]))

    described_class.perform_now(import.id)

    expect(import.reload.status).to eq("awaiting_input")
    expect(import.preview.dig("accounts", 0, "name")).to eq("NuBank")
  end

  # Reading must not touch the user's data — that only happens on confirmation.
  it "writes nothing" do
    import = create(:import, user:, file_path: export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]]))

    expect { described_class.perform_now(import.id) }.not_to change(Transaction, :count)
    expect(user.accounts).to be_empty
  end

  it "keeps the file, which the write pass still needs" do
    path = export([["01.08.2026", "Mercado", "Mercado", -50.0, "Pago"]])
    described_class.perform_now(create(:import, user:, file_path: path).id)

    expect(File).to exist(path)
  end

  it "records a failure when the file cannot be read" do
    import = create(:import, user:, file_path: "/nowhere/missing.xls")

    expect { described_class.perform_now(import.id) }.not_to raise_error
    expect(import.reload).to have_attributes(status: "failed")
  end

  it "records a failure when the spreadsheet is malformed" do
    path = Rails.root.join("tmp/imports", Rails.env, "#{SecureRandom.uuid}.xls")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "not a spreadsheet")

    described_class.perform_now(create(:import, user:, file_path: path.to_s).id)

    expect(Import.last.status).to eq("failed")
  end

  it "ignores an import that has already moved on" do
    import = create(:import, user:, status: "awaiting_input")

    expect { described_class.perform_now(import.id) }.not_to(change { import.reload.status })
  end

  it "ignores an import that no longer exists" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
