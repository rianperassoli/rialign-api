# A bank account / wallet (checking, savings, cash...).
# `initial_balance` is the opening balance; the current balance is derived from
# paid transactions (see Accounts::BalanceCalculator).
#
# Two independent ways to take an account out of the picture:
#  - `exclude_from_total`: still listed and still usable, but its balance does
#    not reach the consolidated total.
#  - archiving (SoftDeletable): hidden everywhere until restored.
#
# `currency` is what the account holds. Totals and reports are in BASE_CURRENCY
# and nothing is converted, so an account in any other currency keeps its own
# balance but never reaches the consolidated total or the reports.
class Account < ApplicationRecord
  include SoftDeletable

  ACCOUNT_TYPES = %w[checking savings cash other].freeze
  BASE_CURRENCY = "BRL".freeze
  CURRENCIES = %w[BRL USD EUR GBP].freeze

  belongs_to :user
  has_many :transactions, dependent: :destroy

  # Accounts that make up the consolidated balance.
  scope :counted, -> { where(exclude_from_total: false, currency: BASE_CURRENCY) }
  scope :in_base_currency, -> { where(currency: BASE_CURRENCY) }

  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES }
  validates :initial_balance, numericality: true
  validates :currency, inclusion: { in: CURRENCIES }

  def counted?
    !exclude_from_total && currency == BASE_CURRENCY
  end
end
