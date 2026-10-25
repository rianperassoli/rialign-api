# Links an invoice payment to the card charges it settled.
#
# Paying an invoice (CreditCards::PayInvoice) points each settled charge at the
# payment leg. Removing the payment cancels it, Organizze's "cancelar
# pagamento": the charges it settled go back to pending, so the invoice reopens
# and the money returns to the account in the same step.
module InvoiceSettlement
  extend ActiveSupport::Concern

  REMAINDER_PAID = "This payment left a remaining balance that a later invoice payment " \
                   "already settled; undo that payment first".freeze

  included do
    belongs_to :settled_by, class_name: "Transaction", optional: true
    has_many :settled_charges, class_name: "Transaction", foreign_key: :settled_by_id,
                               inverse_of: :settled_by, dependent: nil
  end

  # Unscoped so a charge archived since still lets go of the link.
  def archive!
    return super if archived?
    raise ActiveRecord::RecordNotDestroyed.new(REMAINDER_PAID, self) if remainder_already_paid?

    self.class.transaction do
      self.class.unscoped.where(settled_by_id: id)
          .update_all(paid: false, settled_by_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      super
    end
  end

  private

  # A partial payment carries what it left unpaid onto the next invoice as a
  # card leg of the same payment (see CreditCards::PayInvoice). Once a later
  # payment has settled that leg, undoing this one would pull a charge out
  # from under it — whichever leg is removed first.
  def remainder_already_paid?
    return false if transfer_id.blank?

    self.class.where(user_id:, transfer_id:).where.not(credit_card_id: nil).paid.exists?
  end
end
