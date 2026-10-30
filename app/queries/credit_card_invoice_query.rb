# Resolves a credit card's invoice for a given reference month.
#
# An invoice is named after the month it is DUE, which is how Organizze names
# them and how people refer to them ("the July bill" is the one you pay in
# July). Each card charge stores the invoice it belongs to
# (Transaction#invoice_month): by default the cycle its date falls in — with the
# common closing 28 / due 5 setup, the July invoice covers
# (May closing, June closing] — but a charge can sit on a later invoice, e.g.
# one pushed forward in Organizze. `period` is the nominal cycle, for display.
# When the card is due after it closes in the same month, the cycle closes in
# the due month itself. Both days are clamped for short months.
#
# Status:
#   paid   - the invoice has charges and none is pending
#   closed - past the closing date but still carrying pending charges
#   open   - the invoice is still accumulating charges
class CreditCardInvoiceQuery
  def initialize(card, month: Date.current.beginning_of_month)
    @card = card
    @month = month.beginning_of_month
  end

  def call
    # Charges and credits alike; both totals are net of credits.
    transactions = @card.transactions
                        .where(invoice_month: @month)
                        .order(date: :asc, id: :asc)
    total = transactions.charged_total
    pending = transactions.pending.charged_total

    {
      month: @month.strftime("%Y-%m"),
      period: period,
      closing_date: period[:to],
      due_date: due_date,
      total: total,
      pending: pending,
      status: status(total:, pending:),
      # Whether the invoices either side are paid: a charge cannot be moved
      # onto one (see Transaction#invoice_month_not_paid).
      previous_paid: self.class.paid?(@card, @month << 1),
      next_paid: self.class.paid?(@card, @month >> 1),
      transactions: transactions,
      payments: payments(transactions)
    }
  end

  # An invoice is paid once it has charges and none is still pending — the
  # same rule as the "paid" status. `except` leaves one charge out, so a charge
  # can ask about the invoice it is being moved to.
  def self.paid?(card, month, except: nil)
    charges = card.transactions.where(invoice_month: month.beginning_of_month)
    charges = charges.where.not(id: except) if except
    charges.exists? && !charges.pending.exists?
  end

  def period
    @period ||= { from: closing_date_in(closing_month << 1) + 1, to: closing_date_in(closing_month) }
  end

  # Closing date falling in `month`, clamped for short months.
  def self.closing_date_in(card, month)
    Date.new(month.year, month.month, [card.closing_day, month.end_of_month.day].min)
  end

  private

  # The payments that settled charges on this invoice; removing one reopens
  # what it settled. Every account leg of the payment is listed: an imported
  # invoice paid in two goes is one payment of two legs (see
  # Imports::InvoicePaymentLinking). An imported invoice with no payment in the
  # export reads paid with none listed.
  def payments(transactions)
    user_transactions = @card.user.transactions
    settlements = user_transactions.where(id: transactions.select(:settled_by_id)).select(:transfer_id)
    user_transactions.where(transfer_id: settlements, credit_card_id: nil).order(date: :asc, id: :asc)
  end

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
