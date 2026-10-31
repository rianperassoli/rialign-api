require "csv"

module Transactions
  # The activity list as a spreadsheet, filtered exactly as on screen (the
  # caller hands it the TransactionsQuery relation): every page of it, oldest
  # first. Written for Excel in Brazil, like Organizze's export: ";" between
  # columns, a decimal comma and a UTF-8 mark so accents open right.
  class ExportCsv
    HEADERS = ["Data", "Descrição", "Categoria", "Conta/Cartão", "Valor", "Situação"].freeze

    def initialize(transactions)
      @transactions = transactions
    end

    def call
      rows = @transactions.reorder(date: :asc, id: :asc).includes(:account, :credit_card, category: :parent).to_a
      csv = CSV.generate(col_sep: ";") do |lines|
        lines << HEADERS
        rows.each { |transaction| lines << row(transaction) }
      end
      "﻿#{csv}"
    end

    private

    def row(transaction)
      [transaction.date.strftime("%d/%m/%Y"), transaction.description, category(transaction),
       (transaction.account || transaction.credit_card).name, amount(transaction),
       transaction.paid ? "Pago" : "Não pago"]
    end

    def category(transaction)
      category = transaction.category
      return unless category

      category.parent ? "#{category.parent.name} › #{category.name}" : category.name
    end

    def amount(transaction)
      format("%.2f", transaction.signed_amount).tr(".", ",")
    end
  end
end
