# Resolves a credit card's invoice for a given reference month.
#
# An invoice is named after the month it is DUE, which is how Organizze names
# them and how people refer to them ("the July bill" is the one you pay in
# July). The charges it gathers are the cycle that closes BEFORE that due date:
# with the common closing 28 / due 5 setup, the July invoice covers
# (May closing, June closing]. When the card is due after it closes in the same
# month, the cycle closes in the due month itself. Both days are clamped for
# short months.
#
# Status:
#   paid   - the cycle has charges and none is pending
#   closed - past the closing date but still carrying pending charges
#   open   - the cycle is still accumulating charges
class CreditCardInvoiceQuery
  def initialize(card, month: Date.current.beginning_of_month)
    @card = card
    @month = month.beginning_of_month
  end

  def call
    transactions = @card.transactions.expense
                        .between(period[:from], period[:to])
                        .order(date: :asc, id: :asc)
    total = transactions.sum(:amount)
    pending = transactions.pending.sum(:amount)

    {
      month: @month.strftime("%Y-%m"),
      period: period,
      closing_date: period[:to],
      due_date: due_date,
      total: total,
      pending: pending,
      status: status(total:, pending:),
      transactions: transactions
    }
  end

  def period
    @period ||= { from: closing_date_in(closing_month << 1) + 1, to: closing_date_in(closing_month) }
  end

  # Closing date falling in `month`, clamped for short months.
  def self.closing_date_in(card, month)
    Date.new(month.year, month.month, [card.closing_day, month.end_of_month.day].min)
  end

  private

  # The cycle billed in @month closes in @month when the card is due after it
  # closes, and in the month before otherwise.
  def closing_month
    @closing_month ||= @card.due_day > @card.closing_day ? @month : @month << 1
  end

  def closing_date_in(month)
    self.class.closing_date_in(@card, month)
  end

  def due_date
    Date.new(@month.year, @month.month, [@card.due_day, @month.end_of_month.day].min)
  end

  def status(total:, pending:)
    return "paid" if total.positive? && pending.zero?

    Date.current > period[:to] ? "closed" : "open"
  end
end
