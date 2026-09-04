# A credit card. Expenses booked against a card make up the open invoice
# (see Accounts::BalanceCalculator#credit_card_invoice).
class CreditCard < ApplicationRecord
  include SoftDeletable

  belongs_to :user
  # Default bank account the invoice is paid from.
  belongs_to :payment_account, class_name: "Account", optional: true
  has_many :transactions, dependent: :destroy

  validates :name, presence: true
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }
  validates :closing_day, :due_day,
            numericality: { only_integer: true, in: 1..31 }
  validate :payment_account_belongs_to_user

  # The most recent closing that has already happened — the invoice you are
  # being billed for right now. Charges made after it are accumulating into the
  # next one and are not part of what is currently owed.
  def current_closing_date
    today = Date.current
    this_month = CreditCardInvoiceQuery.closing_date_in(self, today)
    this_month <= today ? this_month : CreditCardInvoiceQuery.closing_date_in(self, today << 1)
  end

  # What is actually owed on the open invoice: every pending charge dated up to
  # the current closing date. Charges dated after it were made in the next
  # cycle and belong to the NEXT invoice, so they are excluded here — while
  # pending charges from earlier cycles are still owed and stay included.
  def open_invoice
    transactions.expense.pending.where(date: ..current_closing_date).sum(:amount)
  end

  # Charges dated after the current closing date: already made, already
  # consuming the limit, but billed only on the NEXT invoice. Complement of
  # #open_invoice — together they are #used_limit.
  def next_invoice
    transactions.expense.pending.where(date: (current_closing_date + 1)..).sum(:amount)
  end

  # Every pending charge consumes the limit, including the ones already booked
  # into the next invoice. This is deliberately broader than #open_invoice.
  def used_limit
    transactions.expense.pending.sum(:amount)
  end

  def available_limit
    credit_limit - used_limit
  end

  private

  def payment_account_belongs_to_user
    return if payment_account.blank? || payment_account.user_id == user_id

    errors.add(:payment_account, "must belong to the same user")
  end
end
