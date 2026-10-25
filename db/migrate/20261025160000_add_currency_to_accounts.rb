class AddCurrencyToAccounts < ActiveRecord::Migration[8.0]
  # The currency an account holds. Totals and reports are in BRL and nothing is
  # converted, so an account in another currency shows its own balance but
  # stays out of the consolidated balance and of income/expense reports.
  def change
    add_column :accounts, :currency, :string, default: "BRL", null: false
  end
end
