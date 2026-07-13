# Resolves a credit card's invoice for a given reference month.
#
# The invoice labelled "July" gathers the card expenses in the cycle that
# CLOSES in July: (June closing, July closing]. `closing_day`/`due_day` are
# clamped for short months, and the due date rolls into the next month when
# the card is due before it closes (the common closing 28 / due 5 setup).
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
    @period ||= { from: closing_date_in(@month << 1) + 1, to: closing_date_in(@month) }
  end

  private

  def closing_date_in(month)
    Date.new(month.year, month.month, [@card.closing_day, month.end_of_month.day].min)
  end

  def due_date
    base = @card.due_day > @card.closing_day ? @month : @month >> 1
    Date.new(base.year, base.month, [@card.due_day, base.end_of_month.day].min)
  end

  def status(total:, pending:)
    return "paid" if total.positive? && pending.zero?

    Date.current > period[:to] ? "closed" : "open"
  end
end
