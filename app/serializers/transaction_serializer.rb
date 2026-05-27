class TransactionSerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      description: object.description,
      kind: object.kind,
      amount: object.amount,
      signed_amount: object.signed_amount,
      date: object.date,
      paid: object.paid,
      notes: object.notes,
      category: category,
      account_id: object.account_id,
      credit_card_id: object.credit_card_id,
      created_at: object.created_at
    }
  end

  # A transaction always has a category (required association).
  def category
    { id: object.category.id, name: object.category.name, kind: object.category.kind }
  end
end
