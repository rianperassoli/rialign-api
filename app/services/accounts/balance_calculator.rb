module Accounts
  # Pure balance math for a user, kept out of models/controllers so the rules
  # live in one place and are trivially unit-testable.
  #
  # Conventions:
  #  - Account balance counts only PAID transactions booked to that account:
  #      initial_balance + sum(income) - sum(expense)
  #  - Consolidated balance = sum of every (kept) account balance, skipping the
  #    ones flagged `exclude_from_total`. Those still report their own balance;
  #    they just do not feed the headline number.
  #  - A credit card open invoice = pending expenses up to the current closing
  #    date; the next invoice is what has accumulated after it; available limit
  #    subtracts ALL pending charges (see CreditCard).
  class BalanceCalculator < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      success(
        consolidated_balance: consolidated_balance,
        accounts: account_balances,
        credit_cards: credit_card_invoices
      )
    end

    # Balance for a single account (used by serializers).
    def account_balance(account)
      paid = account.transactions.paid
      account.initial_balance + paid.income.sum(:amount) - paid.expense.sum(:amount)
    end

    private

    def account_balances
      @user.accounts.map do |account|
        { account:, balance: account_balance(account) }
      end
    end

    def consolidated_balance
      account_balances.sum { |row| row[:account].exclude_from_total? ? 0 : row[:balance] }
    end

    def credit_card_invoices
      @user.credit_cards.map do |card|
        { credit_card: card, open_invoice: card.open_invoice, next_invoice: card.next_invoice,
          available_limit: card.available_limit }
      end
    end
  end
end
