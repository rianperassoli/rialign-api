class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :color
      t.datetime :archived_at

      t.timestamps
    end

    add_index :categories, %i[user_id kind]
    add_index :categories, :archived_at
  end
end
