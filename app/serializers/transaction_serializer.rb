class TransactionSerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      description: object.description,
      kind: object.kind,
      amount: object.amount,
      signed_amount: object.signed_amount,
      # The account's currency; cards are always in the base currency.
      currency: object.account&.currency || Account::BASE_CURRENCY,
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
  # marker for money-movement legs. A card charge also names its invoice.
  def source_attributes
    {
      account_id: object.account_id,
      credit_card_id: object.credit_card_id,
      invoice_month: object.invoice_month&.strftime("%Y-%m"),
      settled_by_id: object.settled_by_id,
      transfer_id: object.transfer_id,
      counterpart_account_id: object.counterpart_account_id
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

    category = object.category
    { id: category.id, name: category.name, kind: category.kind, color: category.display_color,
      icon: category.display_icon,
      parent: category.parent && { id: category.parent.id, name: category.parent.name } }
  end
end
