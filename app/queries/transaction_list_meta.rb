# What the activity list sends beside its page of entries, worked out from
# the same filters (see TransactionsQuery):
#
#  - totals: what the whole filtered list adds up to, every page of it —
#    Organizze's "Total com o termo …" and list total. Transfers stay out,
#    invoice payments included, as Organizze adds it up: they only move money,
#    and a payment would count the card purchases a second time (October
#    2026: 37,32 with them out).
#  - open_invoices: on the cash flow, the invoices still to be paid that fall
#    due in the period, listed among the entries (see OpenInvoicesQuery) —
#    unless the filters narrow the list to something an invoice is not.
class TransactionListMeta
  # Filters an unpaid invoice can never match: it is an expense, still to be
  # paid, with no category and on no single card.
  NOT_INVOICES = { type: %w[income transfer fixed installments], paid: %w[true], kind: %w[income] }.freeze

  def initialize(user, scope, filters)
    @user = user
    @scope = scope
    @filters = filters
  end

  def call
    { totals:, open_invoices: }.compact
  end

  private

  def totals
    sums = @scope.reorder(nil).non_transfer.group(:kind).sum(:amount)
    income = sums.fetch("income", 0)
    expense = sums.fetch("expense", 0)
    { income:, expense:, net: income - expense }
  end

  def open_invoices
    return unless @filters[:view] == "cash_flow" && !narrowed_past_invoices?

    period = Date.parse(@filters[:from].to_s)..Date.parse(@filters[:to].to_s)
    OpenInvoicesQuery.new(@user, period:, account_id: @filters[:account_id].presence).call
  rescue Date::Error
    nil
  end

  def narrowed_past_invoices?
    %i[category_id credit_card_id search].any? { |key| @filters[key].present? } ||
      NOT_INVOICES.any? { |key, values| values.include?(@filters[key].to_s) }
  end
end
