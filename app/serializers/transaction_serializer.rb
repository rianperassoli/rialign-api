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
      created_at: object.created_at,
      **source_attributes,
      **series_attributes
    }
  end

  # Where the transaction is booked: bank account or card, plus the transfer
  # marker for money-movement legs.
  def source_attributes
    {
      account_id: object.account_id,
      credit_card_id: object.credit_card_id,
      transfer_id: object.transfer_id
    }
  end

  # Series metadata: shared id plus "3/12" style fields on installment legs.
  def series_attributes
    {
      series_id: object.series_id,
      installment_number: object.installment_number,
      installment_total: object.installment_total
    }
  end

  # Regular transactions always have a category; transfer/settlement legs don't.
  def category
    return nil if object.category.blank?

    { id: object.category.id, name: object.category.name, kind: object.category.kind, color: object.category.color }
  end
end
