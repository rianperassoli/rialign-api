# Income or expense entry.
#
# A transaction is booked against EXACTLY ONE source: a bank Account or a
# CreditCard. `amount` is always stored as a positive decimal; `kind`
# determines its effect on balances. `paid` distinguishes settled money
# (counts toward balance) from scheduled/pending money (shown on dashboard
# forecasts only).
class Transaction < ApplicationRecord
  include SoftDeletable

  KINDS = %w[income expense].freeze

  belongs_to :user
  belongs_to :category
  belongs_to :account,     optional: true
  belongs_to :credit_card, optional: true

  scope :income,   -> { where(kind: "income") }
  scope :expense,  -> { where(kind: "expense") }
  scope :paid,     -> { where(paid: true) }
  scope :pending,  -> { where(paid: false) }
  scope :between,  ->(from, to) { where(date: from..to) }

  validates :description, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :amount, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :exactly_one_source
  validate :category_kind_matches
  validate :credit_card_only_for_expenses

  def income?
    kind == "income"
  end

  def expense?
    kind == "expense"
  end

  # Signed value for balance math: income adds, expense subtracts.
  def signed_amount
    income? ? amount : -amount
  end

  private

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
end
