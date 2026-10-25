class AccountSerializer < ApplicationSerializer
  # Pass `balance:` to avoid recomputation when the caller already has it
  # (e.g. dashboard). Falls back to an on-demand calculation otherwise.

  private

  def attributes
    {
      id: object.id,
      name: object.name,
      account_type: object.account_type,
      currency: object.currency,
      initial_balance: object.initial_balance,
      current_balance: current_balance,
      exclude_from_total: object.exclude_from_total,
      # Whether it reaches the consolidated balance (see Account#counted?).
      counted: object.counted?,
      archived: object.archived?,
      created_at: object.created_at
    }
  end

  def current_balance
    opts.fetch(:balance) do
      Accounts::BalanceCalculator.new(user: object.user).account_balance(object)
    end
  end
end
