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

  # Closing date of the cycle currently being billed.
  def current_closing_date
    CreditCardInvoiceQuery.new(self).period[:to]
  end

  # What is actually owed on the open invoice: every pending charge dated up to
  # the current closing date. Charges dated after it were made in the next
  # cycle and belong to the NEXT invoice, so they are excluded here — while
  # pending charges from earlier cycles are still owed and stay included.
  def open_invoice
    transactions.expense.pending.where(date: ..current_closing_date).sum(:amount)
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
