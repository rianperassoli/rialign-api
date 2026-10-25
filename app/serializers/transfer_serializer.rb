# A transfer as one movement, from its legs: the expense leg is the source, the
# income leg the destination. A leg the export left unpaired has only one side,
# so the other account reads nil.
class TransferSerializer < ApplicationSerializer
  private

  def attributes
    source = object.find { |leg| !leg.income? }
    destination = object.find(&:income?)
    leg = source || destination

    {
      transfer_id: leg.transfer_id,
      amount: leg.amount,
      # What reached the destination; differs from `amount` across currencies.
      received_amount: destination&.amount,
      date: leg.date,
      description: leg.description,
      notes: leg.notes,
      from_account_id: source&.account_id,
      to_account_id: destination&.account_id
    }
  end
end
