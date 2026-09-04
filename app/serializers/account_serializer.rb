class AccountSerializer < ApplicationSerializer
  # Pass `balance:` to avoid recomputation when the caller already has it
  # (e.g. dashboard). Falls back to an on-demand calculation otherwise.

  private

  def attributes
    {
      id: object.id,
      name: object.name,
      account_type: object.account_type,
      initial_balance: object.initial_balance,
      current_balance: current_balance,
      exclude_from_total: object.exclude_from_total,
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
