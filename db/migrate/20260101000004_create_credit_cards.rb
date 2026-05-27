class CreateCreditCards < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_cards do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.decimal :credit_limit, precision: 14, scale: 2, null: false, default: "0.0"
      t.integer :closing_day, null: false, default: 1
      t.integer :due_day, null: false, default: 10
      t.datetime :archived_at

      t.timestamps
    end

    add_index :credit_cards, :archived_at
  end
end
