module Accounts
  # Pure balance math for a user, kept out of models/controllers so the rules
  # live in one place and are trivially unit-testable.
  #
  # Conventions:
  #  - Account balance counts only PAID transactions booked to that account:
  #      initial_balance + sum(income) - sum(expense)
  #  - Consolidated balance = sum of every (kept) account balance, skipping the
  #    ones flagged `exclude_from_total` and the ones in another currency (see
  #    Account#counted?). Those still report their own balance; they just do
  #    not feed the headline number.
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
      balances_for([account])[account.id]
    end

    # Balances of several accounts in one grouped query, keyed by account id.
    def balances_for(accounts)
      # Expenses minus income per account: what left it (Transaction.charged_total).
      spent = Transaction.paid.where(account_id: accounts.map(&:id)).group(:account_id).charged_total
      accounts.to_h { |account| [account.id, account.initial_balance - spent.fetch(account.id, 0)] }
    end

    private

    # Worked out once per call: the consolidated balance reads the same rows.
    def account_balances
      @account_balances ||= begin
        accounts = @user.accounts.to_a
        balances = balances_for(accounts)
        accounts.map { |account| { account:, balance: balances[account.id] } }
      end
    end

    def consolidated_balance
      account_balances.sum { |row| row[:account].counted? ? row[:balance] : 0 }
    end

    def credit_card_invoices
      @user.credit_cards.map do |card|
        { credit_card: card, open_invoice: card.open_invoice, next_invoice: card.next_invoice,
          available_limit: card.available_limit }
      end
    end
  end
end
