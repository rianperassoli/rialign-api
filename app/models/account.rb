# A bank account / wallet (checking, savings, cash...).
# `initial_balance` is the opening balance; the current balance is derived from
# paid transactions (see Accounts::BalanceCalculator).
class Account < ApplicationRecord
  include SoftDeletable

  ACCOUNT_TYPES = %w[checking savings cash other].freeze

  belongs_to :user
  has_many :transactions, dependent: :destroy

  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES }
  validates :initial_balance, numericality: true
end
