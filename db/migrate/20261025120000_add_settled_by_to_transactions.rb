class AddSettledByToTransactions < ActiveRecord::Migration[8.0]
  # A card charge settled by paying its invoice now points at the payment that
  # settled it, so removing the payment can reopen exactly those charges
  # (Organizze's "cancelar pagamento"). Charges settled before this — and every
  # imported one, since the export does not pair them — stay unlinked.
  def change
    add_reference :transactions, :settled_by, foreign_key: { to_table: :transactions }, index: true
  end
end
