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

  # The invoice (first day of the month it is DUE) a charge made on `date`
  # lands on by default: the cycle closing on or after it, billed in that
  # closing month when the card is due after it closes, else the month after.
  # A charge can still be moved to a later invoice — see Transaction#invoice_month.
  def invoice_month_for(date)
    closing = CreditCardInvoiceQuery.closing_date_in(self, date)
    closing_month = date <= closing ? date.beginning_of_month : date.beginning_of_month >> 1
    due_day > closing_day ? closing_month : closing_month >> 1
  end

  # The invoice still accumulating charges today — Organizze's "fatura atual".
  def current_invoice_month
    invoice_month_for(Date.current)
  end

  # What is owed up to the current invoice: its pending charges plus any left
  # unpaid on earlier invoices (Organizze's "saldo anterior").
  def open_invoice
    transactions.expense.pending.where(invoice_month: ..current_invoice_month).sum(:amount)
  end

  # Pending charges already booked on later invoices (future installments,
  # charges pushed forward): consuming the limit, but not billed yet. Complement
  # of #open_invoice — together they are #used_limit.
  def next_invoice
    transactions.expense.pending.where(invoice_month: (current_invoice_month >> 1)..).sum(:amount)
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
