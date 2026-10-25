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

    validate :movement_changed_as_pair, on: :update
  end

  def transfer?
    transfer_id.present?
  end

  private

  def movement_changed_as_pair
    return if editing_as_pair || !transfer_id_was
    return unless changed.intersect?(MOVEMENT)

    errors.add(:base, "a transfer leg can only be changed together with the transfer")
  end
end
