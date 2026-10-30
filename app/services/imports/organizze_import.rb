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
  #  - `Situação` is the payment status on an account row — "Pago", or
  #    "Não pago" for an entry scheduled ahead, which stays pending — and the
  #    invoice month on every card row: the invoice a charge belongs to, NOT a
  #    payment status.
  #    Card charges keep that invoice (Organizze lets a charge be pushed to a
  #    later one, so it cannot be re-derived from the date) and are settled
  #    when it is older than the card's first open invoice — the oldest one
  #    the export lists itself (see OrganizzeFormat.first_open_invoice).
  #    Both sides name an invoice after the month it is DUE, so the label in the
  #    file is the same label CreditCardInvoiceQuery uses.
  #  - `Transferências` and `Pagamento de fatura` are money movements, not
  #    spending: each row becomes a transfer leg (a `transfer_id`, no category),
  #    so it moves the balance but stays out of income/expense reports. The two
  #    sides of a transfer are paired afterwards (see TransferPairing); an
  #    invoice payment has no card side in the export, so it stays one leg,
  #    linked to the invoice it paid (see InvoicePaymentLinking).
  #  - A category name can appear with both signs (`Compras` has 757 expenses and
  #    1 income), and Category#kind must match the transaction, so each name maps
  #    to one category PER KIND.
  #
  #  - A positive row on a card sheet ("Estorno", "Reembolso") is a credit: an
  #    income on the card that lowers the invoice it sits on.
  #  - A card charge whose description ends in a parcel ("Tv pai 8/12") is an
  #    installment: the parcel moves into the installment fields and the
  #    parcels of one purchase share a series (see InstallmentSeries).
  #  - When the period reaches into the future, Organizze also lists each open
  #    invoice itself ("Fatura Novembro 2026", no category): on the card sheet,
  #    where it would double the invoice, and as an unpaid bill on the account
  #    that pays it. Rialign builds invoices from their charges and books the
  #    payment when it is made, so those rows are skipped.
  #
  # Rows that cannot be represented are skipped and counted in the report rather
  # than aborting the run: a zero amount (Transaction requires > 0).
  class OrganizzeImport < ApplicationService
    TRANSFER_CATEGORIES = [TransferPairing::CATEGORY, InvoicePaymentLinking::CATEGORY].freeze

    # `open_from` stands in for the first invoice still open on a card whose
    # sheet lists none; charges from it onward are imported pending.
    # `replace_existing` wipes the user's accounts, cards, categories and
    # transactions before importing. The export is a full history, so merging it
    # into existing data would duplicate every row; replacing is the only
    # outcome a user can predict. It happens inside the same transaction as the
    # import, so a failure leaves the old data untouched.
    # `defaults` holds what the export cannot say, keyed by sheet name under
    # `:accounts` and `:credit_cards`: a card's due day and limit, an account's
    # place in the consolidated balance and its `current_balance` — the balance
    # Organizze shows today, from which the opening balance is worked out.
    def initialize(user:, path:, open_from: Date.current.beginning_of_month, defaults: {},
                   replace_existing: false)
      @user = user
      @path = path
      @open_from = open_from.beginning_of_month
      @defaults = defaults.symbolize_keys
      @replace_existing = replace_existing
      @report = Hash.new(0)
      @categories = {}
      # Each joins up rows it is handed as they are imported, once all are in.
      @linkers = [TransferPairing.new, InvoicePaymentLinking.new]
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
        @linkers.each { |linker| @report.merge!(linker.call) }
      end
      success(@report)
    rescue ActiveRecord::RecordInvalid => e
      failure("Row could not be imported: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    # Unscoped so archived records go too, and ordered so nothing is left
    # pointing at a deleted row.
    def wipe_existing
      [Transaction, Recurrence, CreditCard, Account, Category].each do |model|
        @report[:replaced] += model.unscoped.where(user: @user).delete_all
      end
    end

    def import_sheet(sheet)
      source = source_for(sheet.name)
      series = source.is_a?(CreditCard) ? InstallmentSeries.for_sheet(sheet) : {}
      @card_open_from = OrganizzeFormat.first_open_invoice(sheet) || @open_from
      1.upto(sheet.row_count - 1) { |i| import_row(sheet.row(i), source, series_id: series[i]) }
      open_account(source, sheet.name) if source.is_a?(Account)
    end

    def source_for(name)
      if OrganizzeFormat.card_sheet?(name)
        @report[:credit_cards] += 1
        @user.credit_cards.create!({ name: name, closing_day: 31,
                                     due_day: 10 }.merge(defaults_for(:credit_cards, name)))
      else
        @report[:accounts] += 1
        # In reais, whatever the name says: Organizze has no currencies and
        # adds every account into Saldo geral as it is.
        @user.accounts.create!(name: name, initial_balance: 0,
                               **defaults_for(:accounts, name).slice(:exclude_from_total))
      end
    end

    # The export starts every account at zero. Given the balance Organizze shows
    # today, the opening balance is whatever the rows leave unexplained, so the
    # account ends exactly there.
    def open_account(account, name)
      target = defaults_for(:accounts, name)[:current_balance]
      return if target.blank?

      from_rows = Accounts::BalanceCalculator.new(user: @user).account_balance(account)
      account.update!(initial_balance: BigDecimal(target.to_s) - from_rows)
    end

    # Settings arrive as JSON, so the keys are strings; callers in Ruby pass
    # symbols. Normalise both to what create! expects.
    def defaults_for(kind, name)
      entries = @defaults[kind] || {}
      (entries[name] || entries[name.to_s] || {}).symbolize_keys
    end

    def import_row(row, source, series_id: nil)
      date = OrganizzeFormat.parse_date(row[0])
      amount = row[3].to_f
      return @report[:skipped_no_date] += 1 if date.nil?
      return @report[:skipped_zero] += 1 if amount.zero?
      return @report[:skipped_invoice_bills] += 1 if OrganizzeFormat.invoice_bill?(row)

      card = source.is_a?(CreditCard)
      @report[:card_credits] += 1 if card && amount.positive?

      transaction = @user.transactions.create!(attributes_for(row, date:, amount:, source:, series_id:))
      @linkers.each { |linker| linker.add(transaction, category: row[2]) }
      @report[:imported] += 1
    end

    def attributes_for(row, date:, amount:, source:, series_id:)
      kind = amount.negative? ? "expense" : "income"
      base = {
        description: row[1].to_s.strip.presence || "(sem descrição)",
        kind: kind,
        amount: amount.abs,
        date: date,
        notes: row[6].presence,
        **source_attributes(row, source:)
      }
      base.merge!(InstallmentSeries.parcel(row), series_id:) if series_id
      if TRANSFER_CATEGORIES.include?(row[2].to_s.strip)
        base.merge(transfer_id: SecureRandom.uuid)
      else
        base.merge(category: category_for(row[2], kind))
      end
    end

    # A card charge keeps the invoice the file names (nil falls back to the one
    # its date gives) and is settled by it; an account row is settled unless
    # the file says it is still to be paid.
    def source_attributes(row, source:)
      return { account: source, paid: row[4].to_s.strip == OrganizzeFormat::SETTLED } unless source.is_a?(CreditCard)

      { credit_card: source, invoice_month: OrganizzeFormat.parse_invoice_month(row[4]),
        paid: OrganizzeFormat.settled_invoice?(row[4], open_from: @card_open_from) }
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
