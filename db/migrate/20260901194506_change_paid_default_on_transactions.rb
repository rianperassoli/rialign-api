class ChangePaidDefaultOnTransactions < ActiveRecord::Migration[8.0]
  # Drops the column default so that an unset `paid` arrives at the model as
  # nil. That is the only way to tell "the caller said nothing" from "the caller
  # said false" — with any boolean default, one of the two explicit values
  # collides with it. Transaction#default_paid_by_source then fills nil in
  # per source, before validation, so the NOT NULL constraint still holds and
  # existing rows keep their value.
  def change
    change_column_default :transactions, :paid, from: true, to: nil
  end
end
