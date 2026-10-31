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
      current_invoice_month: object.current_invoice_month.strftime("%Y-%m"),
      open_invoice: open_invoice,
      next_invoice: next_invoice,
      available_limit: available_limit,
      **invoices,
      archived: object.archived?,
      created_at: object.created_at
    }
  end

  # The invoice to pay now and the one after it (see CreditCard#invoice_due).
  def invoices
    { invoice_due: object.invoice_due, invoice_after_due: object.invoice_after_due }
  end

  # Both are precomputed by Accounts::BalanceCalculator on the dashboard so the
  # collection does not re-query per card; standalone renders fall back to the
  # model.
  def open_invoice
    opts.fetch(:open_invoice) { object.open_invoice }
  end

  def next_invoice
    opts.fetch(:next_invoice) { object.next_invoice }
  end

  def available_limit
    opts.fetch(:available_limit) { object.available_limit }
  end
end
