module Imports
  # Imports an Organizze .xls export ("movimentações") into a user's account.
  #
  # The export has one worksheet per source, named exactly as it is in Organizze;
  # the ones suffixed "- Cartão" are credit cards, the rest are bank accounts.
  # Every sheet shares the same columns:
  #
  #   Data | Descrição | Categoria | Valor | Situação | Tags | Informações adicionais
  #
  # Mapping rules, all derived from the file itself:
  #
  #  - `Valor` carries the sign: negative is an expense, positive an income. The
  #    stored amount is always positive (`kind` carries the direction).
  #  - `Situação` is "Pago" on every account row, and the invoice month on every
  #    card row — it is the invoice a charge belongs to, NOT a payment status.
  #    Card charges are settled when their invoice is older than `open_from`.
  #    Both sides name an invoice after the month it is DUE, so the label in the
  #    file is the same label CreditCardInvoiceQuery uses.
  #  - `Transferências` and `Pagamento de fatura` are money movements, not
  #    spending: each row becomes a transfer leg (a `transfer_id`, no category),
  #    so it moves the balance but stays out of income/expense reports. Legs are
  #    not paired — the export does not identify the other side.
  #  - A category name can appear with both signs (`Compras` has 757 expenses and
  #    1 income), and Category#kind must match the transaction, so each name maps
  #    to one category PER KIND.
  #
  # Rows that cannot be represented are skipped and counted in the report rather
  # than aborting the run: a zero amount (Transaction requires > 0) and a credit
  # on a card (Transaction forbids income on a credit card — these are the 25
  # "Estorno"/"Reembolso" rows).
  class OrganizzeImport < ApplicationService
    TRANSFER_CATEGORIES = ["Transferências", "Pagamento de fatura"].freeze

    # `open_from` is the first invoice month that is still open; charges from it
    # onward are imported pending.
    # `replace_existing` wipes the user's accounts, cards, categories and
    # transactions before importing. The export is a full history, so merging it
    # into existing data would duplicate every row; replacing is the only
    # outcome a user can predict. It happens inside the same transaction as the
    # import, so a failure leaves the old data untouched.
    # `defaults` holds what the export cannot say, keyed by sheet name under
    # `:accounts` and `:credit_cards`: a card's due day and limit, an account's
    # place in the consolidated balance.
    def initialize(user:, path:, open_from: Date.current.beginning_of_month, defaults: {},
                   replace_existing: false)
      @user = user
      @path = path
      @open_from = open_from.beginning_of_month
      @defaults = defaults.symbolize_keys
      @replace_existing = replace_existing
      @report = Hash.new(0)
      @categories = {}
    end

    def call
      return failure("File not found: #{@path}") unless File.exist?(@path)

      book = Spreadsheet.open(@path)
      # One transaction around the wipe AND the write: a row that cannot be
      # saved rolls the deletion back with it, so a failed import leaves the
      # user exactly as they were rather than empty.
      ApplicationRecord.transaction do
        wipe_existing if @replace_existing
        book.worksheets.each { |sheet| import_sheet(sheet) }
      end
      success(@report)
    rescue ActiveRecord::RecordInvalid => e
      failure("Row could not be imported: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    # Unscoped so archived records go too, and ordered so nothing is left
    # pointing at a deleted row.
    def wipe_existing
      [Transaction, CreditCard, Account, Category].each do |model|
        @report[:replaced] += model.unscoped.where(user: @user).delete_all
      end
    end

    def import_sheet(sheet)
      source = source_for(sheet.name)
      1.upto(sheet.row_count - 1) { |i| import_row(sheet.row(i), source) }
    end

    def source_for(name)
      if OrganizzeFormat.card_sheet?(name)
        @report[:credit_cards] += 1
        @user.credit_cards.create!({ name: name, closing_day: 31,
                                     due_day: 10 }.merge(defaults_for(:credit_cards, name)))
      else
        @report[:accounts] += 1
        @user.accounts.create!({ name: name, initial_balance: 0 }.merge(defaults_for(:accounts, name)))
      end
    end

    # Settings arrive as JSON, so the keys are strings; callers in Ruby pass
    # symbols. Normalise both to what create! expects.
    def defaults_for(kind, name)
      entries = @defaults[kind] || {}
      (entries[name] || entries[name.to_s] || {}).symbolize_keys
    end

    def import_row(row, source)
      date = OrganizzeFormat.parse_date(row[0])
      amount = row[3].to_f
      return @report[:skipped_no_date] += 1 if date.nil?
      return @report[:skipped_zero] += 1 if amount.zero?

      card = source.is_a?(CreditCard)
      return @report[:skipped_card_credit] += 1 if card && amount.positive?

      @user.transactions.create!(attributes_for(row, date:, amount:, source:, card:))
      @report[:imported] += 1
    end

    def attributes_for(row, date:, amount:, source:, card:)
      kind = amount.negative? ? "expense" : "income"
      base = {
        description: row[1].to_s.strip.presence || "(sem descrição)",
        kind: kind,
        amount: amount.abs,
        date: date,
        notes: row[6].presence,
        account: card ? nil : source,
        credit_card: card ? source : nil,
        paid: card ? settled_invoice?(row[4]) : true
      }
      if TRANSFER_CATEGORIES.include?(row[2].to_s.strip)
        base.merge(transfer_id: SecureRandom.uuid)
      else
        base.merge(category: category_for(row[2], kind))
      end
    end

    # Anything on an invoice older than `open_from` has already been paid. A row
    # we cannot place stays pending.
    def settled_invoice?(situacao)
      return true if situacao.to_s.strip == OrganizzeFormat::SETTLED

      month = OrganizzeFormat.parse_invoice_month(situacao)
      month.present? && month < @open_from
    end

    # One category per (name, kind): the same name legitimately carries both
    # directions, and Category#kind has to match the transaction's.
    def category_for(name, kind)
      clean = name.to_s.strip.presence || "Outros"
      @categories[[clean, kind]] ||= begin
        @report[:categories] += 1
        @user.categories.create!(name: clean, kind: kind)
      end
    end
  end
end
