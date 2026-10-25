# Links an invoice payment to the card charges it settled.
#
# Paying an invoice (CreditCards::PayInvoice) points each settled charge at the
# payment leg. Removing the payment cancels it, Organizze's "cancelar
# pagamento": the charges it settled go back to pending, so the invoice reopens
# and the money returns to the account in the same step.
module InvoiceSettlement
  extend ActiveSupport::Concern

  included do
    belongs_to :settled_by, class_name: "Transaction", optional: true
    has_many :settled_charges, class_name: "Transaction", foreign_key: :settled_by_id,
                               inverse_of: :settled_by, dependent: nil
  end

  # Unscoped so a charge archived since still lets go of the link.
  def archive!
    return super if archived?

    self.class.transaction do
      self.class.unscoped.where(settled_by_id: id)
          .update_all(paid: false, settled_by_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      super
    end
  end
end
