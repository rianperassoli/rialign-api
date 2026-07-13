# Income or expense entry.
#
# A transaction is booked against EXACTLY ONE source: a bank Account or a
# CreditCard. `amount` is always stored as a positive decimal; `kind`
# determines its effect on balances. `paid` distinguishes settled money
# (counts toward balance) from scheduled/pending money (shown on dashboard
# forecasts only).
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

  KINDS = %w[income expense].freeze

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :account,     optional: true
  belongs_to :credit_card, optional: true

  scope :income,       -> { where(kind: "income") }
  scope :expense,      -> { where(kind: "expense") }
  scope :paid,         -> { where(paid: true) }
  scope :pending,      -> { where(paid: false) }
  scope :between,      ->(from, to) { where(date: from..to) }
  scope :transfers,    -> { where.not(transfer_id: nil) }
  scope :non_transfer, -> { where(transfer_id: nil) }
  scope :in_series,    ->(series_id) { where(series_id:) }

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

  validate :exactly_one_source
  validate :category_required
  validate :category_kind_matches
  validate :credit_card_only_for_expenses
  validate :installment_fields_consistent

  def income?
    kind == "income"
  end

  def expense?
    kind == "expense"
  end

  # A leg of an account-to-account transfer.
  def transfer?
    transfer_id.present?
  end

  # One leg of an installment purchase (e.g. 3/12).
  def installment?
    installment_number.present?
  end

  # One occurrence of a fixed (monthly recurring) entry.
  def fixed?
    series_id.present? && !installment?
  end

  # Signed value for balance math: income adds, expense subtracts.
  def signed_amount
    income? ? amount : -amount
  end

  private

  # Every regular transaction needs a real category; transfer legs intentionally
  # carry none. Checking the loaded record (not just the id) also rejects a
  # category_id that points to nothing.
  def category_required
    return if transfer? || category.present?

    errors.add(:category, "must be present")
  end

  def exactly_one_source
    sources = [account_id, credit_card_id].compact
    return if sources.size == 1

    errors.add(:base, "must reference exactly one account or credit card")
  end

  def category_kind_matches
    return if category.blank? || category.kind == kind

    errors.add(:category, "kind must match the transaction kind")
  end

  def credit_card_only_for_expenses
    return if credit_card_id.blank? || expense?

    errors.add(:credit_card, "can only hold expense transactions")
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
