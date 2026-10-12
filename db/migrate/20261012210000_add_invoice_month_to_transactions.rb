class AddInvoiceMonthToTransactions < ActiveRecord::Migration[8.0]
  # A card charge now remembers which invoice it belongs to (the first day of
  # the month the invoice is DUE) instead of having it re-derived from its date.
  # Organizze lets a charge be pushed to a later invoice, and the export says
  # which one; deriving from the date silently moved those rows back.
  #
  # Existing charges are backfilled with the date-derived invoice, which is what
  # the app showed until now.
  def up
    add_column :transactions, :invoice_month, :date
    add_index :transactions, %i[credit_card_id invoice_month]

    execute <<~SQL.squish
      UPDATE transactions t
      SET invoice_month = (
        date_trunc('month', t.date)
        + CASE WHEN EXTRACT(DAY FROM t.date) > LEAST(c.closing_day,
                 EXTRACT(DAY FROM date_trunc('month', t.date) + interval '1 month - 1 day'))
               THEN interval '1 month' ELSE interval '0' END
        + CASE WHEN c.due_day > c.closing_day THEN interval '0' ELSE interval '1 month' END
      )::date
      FROM credit_cards c
      WHERE t.credit_card_id = c.id
    SQL
  end

  def down
    remove_index :transactions, %i[credit_card_id invoice_month]
    remove_column :transactions, :invoice_month
  end
end
