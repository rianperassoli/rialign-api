class CreditCardSerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      name: object.name,
      credit_limit: object.credit_limit,
      closing_day: object.closing_day,
      due_day: object.due_day,
      payment_account_id: object.payment_account_id,
      open_invoice: open_invoice,
      available_limit: object.credit_limit - open_invoice,
      archived: object.archived?,
      created_at: object.created_at
    }
  end

  def open_invoice
    opts.fetch(:open_invoice) do
      object.transactions.expense.pending.sum(:amount)
    end
  end
end
