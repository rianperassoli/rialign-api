class AddExcludeFromTotalToAccounts < ActiveRecord::Migration[8.0]
  # Some accounts are tracked but should not move the headline number — a
  # foreign-currency wallet, money held for someone else, a side ledger. The
  # account stays fully active (it lists, it takes transactions, it has its own
  # balance); only the consolidated total skips it. Independent of archiving,
  # which hides the account altogether.
  def change
    add_column :accounts, :exclude_from_total, :boolean, default: false, null: false
  end
end
