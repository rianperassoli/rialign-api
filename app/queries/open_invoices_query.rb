# The card invoices still to be paid that fall due in a period: Organizze's
# cash flow lists each as a line on its due date ("Fatura NuBank - Cartão"),
# the money that will leave the account to pay it. A paid invoice needs no
# line, its payment is already an entry on the account.
#
# Each invoice is read through CreditCardInvoiceQuery, so the due date and
# what is pending follow the same rules as the invoice screen. `account_id`
# keeps the cards paid from that account.
class OpenInvoicesQuery
  def initialize(user, period:, account_id: nil)
    @user = user
    @period = period
    @account_id = account_id
  end

  def call
    cards.flat_map { |card| months.filter_map { |month| line(card, month) } }.sort_by { |line| line[:due_date] }
  end

  private

  def cards
    scope = @user.credit_cards
    @account_id ? scope.where(payment_account_id: @account_id) : scope
  end

  def months
    first = @period.begin.beginning_of_month
    (0..((@period.end.year * 12) + @period.end.month - (first.year * 12) - first.month)).map { |i| first >> i }
  end

  def line(card, month)
    invoice = CreditCardInvoiceQuery.new(card, month:).call
    return unless invoice[:pending].positive? && @period.cover?(invoice[:due_date])

    { credit_card_id: card.id, name: card.name, month: invoice[:month], due_date: invoice[:due_date],
      amount: invoice[:pending], status: invoice[:status] }
  end
end
