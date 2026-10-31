# A transaction carrying a `transfer_id` is one leg of a money movement: an
# account-to-account transfer (two legs, see Transfers::CreateTransfer) or an
# invoice payment (one leg, see CreditCards::PayInvoice).
#
# A leg cannot change what it moves on its own: editing the amount of one side
# of a transfer left the two accounts out of balance. What it moves — amount,
# date, kind, account, paid — changes through Transfers::UpdateTransfer, which
# edits every leg together and marks them `editing_as_pair`; on its own a leg
# only takes a new description or notes.
module TransferLeg
  extend ActiveSupport::Concern

  MOVEMENT = %w[amount date kind account_id credit_card_id paid transfer_id].freeze

  included do
    attr_accessor :editing_as_pair

    # Every leg of the same transfer, this one included.
    has_many :transfer_legs, class_name: "Transaction", primary_key: :transfer_id,
                             foreign_key: :transfer_id, inverse_of: false, dependent: nil

    validate :movement_changed_as_pair, on: :update
  end

  class_methods do
    # Organizze lists a transfer once, "from → to": where both legs of one are
    # in the list, its incoming leg drops out and the outgoing one stands for
    # it. Narrowed to the destination account, only the incoming leg is there,
    # and it stays.
    def one_row_per_transfer
      paired_incoming = transfers.income.where(transfer_id: transfers.expense.select(:transfer_id))
      where.not(id: paired_incoming.unscope(:order).select(:id))
    end
  end

  def transfer?
    transfer_id.present?
  end

  # The account on the other side of an account-to-account transfer; nil for
  # an invoice payment or a leg whose partner is gone.
  def counterpart_account_id
    return unless transfer?

    transfer_legs.find { |leg| leg.id != id }&.account_id
  end

  private

  def movement_changed_as_pair
    return if editing_as_pair || !transfer_id_was
    return unless changed.intersect?(MOVEMENT)

    errors.add(:base, "a transfer leg can only be changed together with the transfer")
  end
end
