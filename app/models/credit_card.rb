# A credit card. Expenses booked against a card make up the open invoice
# (see Accounts::BalanceCalculator#credit_card_invoice).
class CreditCard < ApplicationRecord
  include SoftDeletable

  belongs_to :user
  has_many :transactions, dependent: :destroy

  validates :name, presence: true
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }
  validates :closing_day, :due_day,
            numericality: { only_integer: true, in: 1..31 }
end
