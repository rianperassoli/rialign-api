class AddSeriesToTransactions < ActiveRecord::Migration[8.0]
  def change
    # Installment purchases and fixed (monthly recurring) entries are stored as
    # pre-materialized rows sharing one `series_id` (see
    # Transactions::CreateSeries). Installment legs also carry number/total so
    # the UI can show "3/12"; fixed legs carry only the series id.
    add_column :transactions, :series_id, :uuid
    add_column :transactions, :installment_number, :integer
    add_column :transactions, :installment_total, :integer
    add_index  :transactions, :series_id
  end
end
