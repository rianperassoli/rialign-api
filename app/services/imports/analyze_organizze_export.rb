module Imports
  # Reads an export WITHOUT writing anything, so the user can be shown what is
  # in it and asked for the few things the file cannot answer: a card's due day
  # and credit limit, which invoice is still open, which accounts stay out
  # of the consolidated balance, and each account's balance today (the file has
  # no opening balance).
  #
  # The closing day IS derivable, so it comes back pre-filled: grouping a card's
  # charges by the invoice printed on them exposes the cycle. The due day is
  # NOT — the dates on "Pagamento de fatura" rows say when the user chose to pay
  # (often days early), not when the bill was due, so guessing from them would
  # be wrong more often than not.
  class AnalyzeOrganizzeExport < ApplicationService
    # How many recent invoices the closing day is read from. A card's closing
    # day changes over the years — this export spans seven of them, and the
    # whole history points at a day the card no longer uses — so only the
    # current behaviour counts.
    RECENT_INVOICES = 12

    def initialize(path:)
      @path = path
    end

    def call
      return failure("File not found: #{@path}") unless File.exist?(@path)

      accounts = []
      cards = []
      Spreadsheet.open(@path).worksheets.each do |sheet|
        rows = sheet.row_count - 1
        next if rows.negative?

        if OrganizzeFormat.card_sheet?(sheet.name)
          cards << card_preview(sheet, rows)
        else
          accounts << { name: sheet.name, rows: rows, balance: rows_balance(sheet).to_s("F") }
        end
      end

      success(accounts: accounts, credit_cards: cards)
    end

    private

    # What the account would hold today from its rows alone — the settled ones,
    # as the import counts them (an entry still to be paid, a projected invoice
    # or one dated ahead does not move it yet; see Accounts::BalanceCalculator).
    # The export carries no opening balance, so this is what the user corrects
    # to the balance Organizze shows (see OrganizzeImport's `current_balance`).
    def rows_balance(sheet)
      1.upto(sheet.row_count - 1).sum(BigDecimal(0)) do |i|
        row = sheet.row(i)
        counted = OrganizzeFormat.settled_account_row?(row) &&
                  OrganizzeFormat.parse_date(row[OrganizzeFormat::DATE])&.<=(Date.current)
        counted ? BigDecimal(row[OrganizzeFormat::AMOUNT].to_f.to_s) : 0
      end
    end

    def card_preview(sheet, rows)
      spans = invoice_spans(sheet)
      {
        name: sheet.name,
        rows: rows,
        closing_day: infer_closing_day(spans),
        invoice_months: spans.keys.sort.map { |m| m.strftime("%Y-%m") }
      }
    end

    # First and last charge date on each invoice.
    def invoice_spans(sheet)
      1.upto(sheet.row_count - 1).each_with_object({}) do |i, acc|
        row = sheet.row(i)
        # A projected invoice row is dated on its due day, not on a purchase.
        next if OrganizzeFormat.invoice_bill?(row)

        month = OrganizzeFormat.parse_invoice_month(row[OrganizzeFormat::STATUS])
        date = OrganizzeFormat.parse_date(row[OrganizzeFormat::DATE])
        next if month.nil? || date.nil?

        span = acc[month] ||= { min: date, max: date }
        span[:min] = [span[:min], date].min
        span[:max] = [span[:max], date].max
      end
    end

    # The closing date is not observable, but it is bounded: everything on one
    # invoice was charged on or before it, and everything on the next after it.
    # So each pair of consecutive invoices pins it to a window, and the right
    # closing day is the one that lands inside the most windows. Reading the
    # last charge of a cycle instead would be off by however many days the user
    # simply did not spend.
    def infer_closing_day(spans)
      windows = boundary_windows(spans).last(RECENT_INVOICES)
      return 31 if windows.empty?

      (1..31).max_by { |day| [windows.count { |window| window.any? { |date| closes_on?(date, day) } }, day] }
    end

    def boundary_windows(spans)
      months = spans.keys.sort
      months.each_cons(2).filter_map do |current, following|
        window = spans[current][:max]..(spans[following][:min] - 1)
        window unless window.first > window.last
      end
    end

    # A short month closes on its last day, so day 31 "is" the 28th in February.
    def closes_on?(date, day)
      date.day == [day, date.end_of_month.day].min
    end
  end
end
