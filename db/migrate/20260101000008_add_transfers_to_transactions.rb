class AddTransfersToTransactions < ActiveRecord::Migration[8.0]
  def change
    # A transfer is modelled as two linked transactions sharing one
    # `transfer_id`: an expense on the source account and an income on the
    # destination account (see Transfers::CreateTransfer).
    add_column :transactions, :transfer_id, :uuid
    add_index  :transactions, :transfer_id

    # Transfer legs carry no user category, so the FK must allow NULL.
    change_column_null :transactions, :category_id, true
  end
end
