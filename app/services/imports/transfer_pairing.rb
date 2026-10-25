module Imports
  # Joins the two sides of each transfer found in an Organizze export.
  #
  # The export lists a transfer once per account — an expense on the sheet it
  # left, an income on the sheet it arrived at — and never says which rows
  # belong together. Organizze books both sides on the same day for the same
  # value, so an outgoing leg pairs with an incoming one of the same date and
  # amount on a different account, first come first served when several match.
  # A paired transfer then shares one transfer_id, so it is edited and deleted
  # as one movement (see TransferLeg). What finds no partner — its other side
  # sat on an account the export left out, typically an archived one — stays a
  # one-sided leg, which still moves its own balance correctly.
  class TransferPairing
    CATEGORY = "Transferências".freeze

    def initialize
      @legs = []
    end

    # Collects a leg as the import creates it, if its row is a transfer.
    def add(leg, category:)
      @legs << leg if category.to_s.strip == CATEGORY
    end

    # Pairs what was collected and reports it for the import summary.
    def call
      incoming = @legs.select(&:income?).group_by { |leg| key(leg) }
      paired = @legs.reject(&:income?).count do |outgoing|
        partner = take_partner(incoming[key(outgoing)], outgoing)
        partner && Transaction.where(id: partner.id).update_all(transfer_id: outgoing.transfer_id) # rubocop:disable Rails/SkipsModelValidations
      end
      { transfers_paired: paired, transfers_unpaired: @legs.size - (paired * 2) }
    end

    private

    def key(leg)
      [leg.date, leg.amount]
    end

    def take_partner(candidates, outgoing)
      index = candidates&.index { |leg| leg.account_id != outgoing.account_id }
      candidates.delete_at(index) if index
    end
  end
end
