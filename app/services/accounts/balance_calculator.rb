module Accounts
  # Pure balance math for a user, kept out of models/controllers so the rules
  # live in one place and are trivially unit-testable.
  #
  # Conventions:
  #  - Account balance counts only PAID transactions booked to that account:
  #      initial_balance + sum(income) - sum(expense)
  #  - Consolidated balance = sum of every (kept) account balance.
  #  - A credit card's open invoice = sum of UNPAID expenses booked to it.
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
      account_balances.sum { |row| row[:balance] }
    end

    def credit_card_invoices
      @user.credit_cards.map do |card|
        open_invoice = card.transactions.expense.pending.sum(:amount)
        { credit_card: card, open_invoice:, available_limit: card.credit_limit - open_invoice }
      end
    end
  end
end
