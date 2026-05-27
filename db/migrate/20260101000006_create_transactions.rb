class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.references :credit_card, foreign_key: true

      t.string  :description, null: false
      t.string  :kind, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.date    :date, null: false
      t.boolean :paid, null: false, default: true
      t.text    :notes
      t.datetime :archived_at

      t.timestamps
    end

    add_index :transactions, %i[user_id date]
    add_index :transactions, %i[user_id kind]
    add_index :transactions, :archived_at
  end
end
