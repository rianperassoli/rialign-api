class AddPaymentAccountToCreditCards < ActiveRecord::Migration[8.0]
  def change
    # The bank account the card invoice is paid from by default.
    # Nullable: a card may exist before a payment account is chosen.
    add_reference :credit_cards, :payment_account,
                  foreign_key: { to_table: :accounts }, null: true
  end
end
