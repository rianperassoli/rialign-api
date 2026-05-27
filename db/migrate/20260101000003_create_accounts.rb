class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :account_type, null: false, default: "checking"
      t.decimal :initial_balance, precision: 14, scale: 2, null: false, default: "0.0"
      t.datetime :archived_at

      t.timestamps
    end

    add_index :accounts, :archived_at
  end
end
