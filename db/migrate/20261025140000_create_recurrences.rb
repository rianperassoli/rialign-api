class CreateRecurrences < ActiveRecord::Migration[8.0]
  # The rule behind a fixed entry with no end date. Occurrences are still real
  # rows sharing the series_id; this only remembers when the series started
  # (its day of the month) and how far ahead it has been created, so it can be
  # kept 12 months ahead (see Recurrences::Extend).
  def change
    create_table :recurrences do |t|
      t.references :user, null: false, foreign_key: true
      t.uuid :series_id, null: false
      t.date :starts_on, null: false
      t.date :extended_through, null: false
      t.timestamps
    end
    add_index :recurrences, :series_id, unique: true
    add_index :recurrences, %i[user_id extended_through]
  end
end
