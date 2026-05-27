# Serializes the DashboardQuery hash plus account/credit-card balances into a
# single dashboard payload.
class DashboardSerializer < ApplicationSerializer
  # object: DashboardQuery result hash
  # opts[:balances]: Accounts::BalanceCalculator result hash
  private

  def attributes
    {
      period: object[:period],
      totals: object[:totals],
      forecast: object[:forecast],
      by_category: object[:by_category],
      consolidated_balance: balances[:consolidated_balance],
      accounts: serialized_accounts,
      credit_cards: serialized_cards
    }
  end

  def balances
    @balances ||= opts.fetch(:balances)
  end

  def serialized_accounts
    balances[:accounts].map do |row|
      AccountSerializer.new(row[:account], balance: row[:balance]).as_json
    end
  end

  def serialized_cards
    balances[:credit_cards].map do |row|
      CreditCardSerializer.new(row[:credit_card], open_invoice: row[:open_invoice]).as_json
    end
  end
end
