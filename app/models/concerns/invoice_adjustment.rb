# Keeps a paid invoice honest when a purchase on it changes afterwards.
#
# Once an invoice is paid its charges are settled, and the payment covered
# exactly what they added up to. Raising one of them, lowering it, deleting it
# or moving it off the invoice used to leave the difference nowhere: the
# invoice still read paid, nobody owed the extra and nothing gave back the
# excess. As in Organizze, the difference now goes on to the next invoice
# still open, the way a partial payment carries what was left (see
# CreditCards::PayInvoice):
#
#  - more than was paid: a charge for the difference, to be paid with it;
#  - less (or the purchase gone): a credit for the difference, lowering it.
#
# The adjustment is a leg of the payment that settled the purchase (same
# `transfer_id`), so it stays out of reports — the purchase itself already
# reports the right amount — and goes away when the payment is cancelled,
# which reopens the purchase at its new amount anyway.
#
# A purchase moved to another invoice or card is pending there: that invoice
# is not the one that was paid.
module InvoiceAdjustment
  extend ActiveSupport::Concern

  included do
    after_update :carry_settled_difference
  end

  def archive!
    return super if archived? || !settled_charge?(credit_card_id:, paid:, transfer_id:)

    self.class.transaction do
      carry_difference(-invoice_value(kind:, amount:), card_id: credit_card_id, month: invoice_month,
                                                       payment_id: settled_by_id)
      super
    end
  end

  private

  # Declared after the invoice is worked out (see Transaction), so a date
  # change that lands on another invoice counts as a move.
  def unsettle_when_moved
    return unless credit_card_id && credit_card_id_was && transfer_id.nil?
    return unless credit_card_id_changed? || invoice_month_changed?

    self.paid = false
    self.settled_by_id = nil
  end

  def carry_settled_difference
    return unless settled_charge?(credit_card_id: credit_card_id_before_last_save, paid: paid_before_last_save,
                                  transfer_id: transfer_id_before_last_save)

    was = invoice_value(kind: kind_before_last_save, amount: amount_before_last_save)
    carry_difference(still_settled_value - was, card_id: credit_card_id_before_last_save,
                                                month: invoice_month_before_last_save,
                                                payment_id: settled_by_id_before_last_save)
  end

  # What the purchase now adds to the invoice that was paid: nothing once it
  # left it.
  def still_settled_value
    return 0 if saved_change_to_credit_card_id? || saved_change_to_invoice_month? || !paid

    invoice_value(kind:, amount:)
  end

  # A charge adds to the invoice, a credit takes off it.
  def invoice_value(kind:, amount:)
    kind == "income" ? -amount : amount
  end

  def settled_charge?(credit_card_id:, paid:, transfer_id:)
    credit_card_id.present? && paid && transfer_id.nil?
  end

  def carry_difference(difference, card_id:, month:, payment_id:)
    return if difference.zero?

    card = CreditCard.unscoped.find(card_id)
    payment = self.class.unscoped.find_by(id: payment_id) if payment_id
    self.class.create!(
      user_id:, credit_card: card, kind: difference.positive? ? "expense" : "income", amount: difference.abs,
      date: Date.current, invoice_month: next_open_invoice(card, month), paid: false,
      transfer_id: payment&.transfer_id || SecureRandom.uuid,
      description: "Adjustment to the #{month.strftime("%Y-%m")} invoice: #{description}"
    )
  end

  def next_open_invoice(card, month)
    following = month >> 1
    following >>= 1 while CreditCardInvoiceQuery.paid?(card, following)
    following
  end
end
