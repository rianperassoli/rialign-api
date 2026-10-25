# Income or expense entry.
#
# A transaction is booked against EXACTLY ONE source: a bank Account or a
# CreditCard. `amount` is always stored as a positive decimal; `kind`
# determines its effect on balances. On a card, an expense is a charge and an
# income is a credit (refund, "estorno") that lowers its invoice. `paid`
# distinguishes settled money (counts toward balance) from scheduled/pending
# money (shown on dashboard forecasts only). What it may point at is ruled by
# TransactionReferences.
#
# A `transfer_id` marks money-movement legs that affect account balances but
# must NOT appear as real spending/earning in income/expense reports:
#   - the two legs of an account-to-account transfer (expense on the source +
#     income on the destination, see Transfers::CreateTransfer)
#   - a credit-card invoice settlement leg (see CreditCards::PayInvoice)
# These are still counted toward account balances but EXCLUDED from reports via
# the `non_transfer` scope (see DashboardQuery).
class Transaction < ApplicationRecord
  include SoftDeletable
  include InvoiceSettlement
  include TransactionReferences
  include TransferLeg

  KINDS = %w[income expense].freeze

  belongs_to :user

  scope :income,       -> { where(kind: "income") }
  scope :expense,      -> { where(kind: "expense") }
  scope :paid,         -> { where(paid: true) }
  scope :pending,      -> { where(paid: false) }
  scope :between,      ->(from, to) { where(date: from..to) }
  scope :transfers,    -> { where.not(transfer_id: nil) }
  scope :non_transfer, -> { where(transfer_id: nil) }
  scope :in_series,    ->(series_id) { where(series_id:) }

  # Reports place a card charge in the month its invoice is due, and anything
  # on an account on its own date — the way Organizze reports card spending.
  REPORT_DATE = Arel.sql("COALESCE(transactions.invoice_month, transactions.date)")
  scope :reported_between, ->(from, to) { where(REPORT_DATE.between(from..to)) }
  # What a report counts as real: settled account money, and every card charge
  # or credit whether its invoice is paid yet or not — the purchase is already
  # made, so the month's spending no longer depends on when the bill is paid.
  scope :booked,    -> { paid.or(where.not(credit_card_id: nil)) }
  # Account entries still scheduled: the forecast. Card charges never are.
  scope :scheduled, -> { pending.where(credit_card_id: nil) }
  # Reports are in Account::BASE_CURRENCY and nothing is converted, so entries
  # on an account in another currency stay out (cards have no currency).
  scope :in_base_currency, lambda {
    where(account_id: nil).or(where(account_id: Account.unscoped.in_base_currency.select(:id)))
  }

  validates :description, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :amount, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :installment_number,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :installment_total,
            numericality: { only_integer: true, greater_than: 1 },
            allow_nil: true

  before_validation :default_paid_by_source, on: :create
  before_validation :assign_invoice_month

  validate :installment_fields_consistent
  validate :invoice_month_not_paid, on: :update

  def income?
    kind == "income"
  end

  # One leg of an installment purchase (e.g. 3/12).
  def installment?
    installment_number.present?
  end

  # One occurrence of a fixed (monthly recurring) entry.
  def fixed?
    series_id.present? && !installment?
  end

  # Accepts the "YYYY-MM" label the API speaks (an invoice is a month), as well
  # as a full date.
  def invoice_month=(value)
    value = "#{value}-01" if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}\z/)
    super
  end

  # Signed value for balance math: income adds, expense subtracts.
  def signed_amount
    income? ? amount : -amount
  end

  # What a set of card transactions adds to the bill: charges minus credits
  # (refunds, "estornos"). On a card an income is a credit that lowers the
  # invoice it sits on, the same way Organizze nets it.
  def self.charged_total
    sum(Arel.sql("CASE WHEN transactions.kind = 'expense' THEN transactions.amount ELSE -transactions.amount END"))
  end

  private

  # `paid` means different things depending on the source, so the default
  # depends on it too: money leaving an account is settled on the spot, while a
  # card charge stays pending until the invoice is paid (only pending charges
  # make up the open invoice — settling them on creation is what made the
  # invoice read zero).
  #
  # The column has no default, so an unset `paid` arrives here as nil and only
  # then is filled in. Any boolean default would collide with one of the two
  # explicit values and swallow it, so `paid: true` on a card charge (an
  # imported or already-settled purchase) is respected, and so is `paid: false`
  # on an account expense (a scheduled payment).
  def default_paid_by_source
    return unless paid.nil?

    self.paid = credit_card_id.blank?
  end

  # A card charge belongs to one invoice, stored as the first day of the month
  # it is due. It defaults to the invoice the date falls in, and follows the
  # date or card when either changes — unless the invoice is set explicitly in
  # the same change, which is how a charge is pushed to a later invoice (and
  # how an import keeps the invoice the file names).
  def assign_invoice_month
    if credit_card.nil?
      self.invoice_month = nil
    elsif invoice_month.nil? || ((date_changed? || credit_card_id_changed?) && !invoice_month_changed?)
      self.invoice_month = credit_card.invoice_month_for(date) if date
    else
      self.invoice_month = invoice_month.beginning_of_month
    end
  end

  # A charge cannot be moved onto an invoice that is already paid: it would
  # reopen a bill that was settled. A closed but unpaid invoice is fine. Only
  # moves are checked — creating a charge (an import, a backdated purchase)
  # files it wherever it belongs.
  def invoice_month_not_paid
    return unless credit_card && invoice_month && invoice_month_changed?
    return unless CreditCardInvoiceQuery.paid?(credit_card, invoice_month, except: id)

    errors.add(:invoice_month, "is already paid")
  end

  # Installment legs must carry number + total + the shared series id, and the
  # number can never exceed the total.
  def installment_fields_consistent
    return if installment_number.blank? && installment_total.blank?

    if installment_number.blank? || installment_total.blank? || series_id.blank?
      errors.add(:base, "installment legs need a number, a total and a series id")
    elsif installment_number > installment_total
      errors.add(:installment_number, "cannot exceed the installment total")
    end
  end
end
