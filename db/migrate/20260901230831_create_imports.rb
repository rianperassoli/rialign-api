class CreateImports < ActiveRecord::Migration[8.0]
  # An import is slow enough (thousands of rows) that the request cannot wait for
  # it, so it becomes a record the client polls: the upload returns immediately
  # and the job fills in `status`, `report` and `error_message`.
  def change
    create_table :imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :filename, null: false
      t.string :file_path, null: false
      t.jsonb :report, null: false, default: {}
      t.string :error_message
      t.timestamps
    end

    add_index :imports, %i[user_id created_at]
  end
end
