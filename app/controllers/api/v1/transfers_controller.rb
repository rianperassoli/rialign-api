module Api
  module V1
    class TransfersController < ApplicationController
      before_action :set_legs, only: %i[show update destroy]

      # GET /api/v1/transfers
      # One row per transfer, with both sides (see TransferSerializer), most
      # recent first. Paged by one leg per transfer — its outgoing side, or the
      # only side an unpaired one has. Invoice payments are left out: they are
      # listed and undone on their invoice.
      def index
        render_page(listed_legs.order(date: :desc, id: :desc)) do |legs|
          sides = current_user.transactions.where(transfer_id: legs.map(&:transfer_id)).group_by(&:transfer_id)
          legs.map { |leg| TransferSerializer.new(sides[leg.transfer_id]).as_json }
        end
      end

      # GET /api/v1/transfers/:id   (:id is the shared transfer_id)
      def show
        render_resource(@legs, serializer: TransferSerializer)
      end

      # POST /api/v1/transfers
      def create
        result = Transfers::CreateTransfer.call(user: current_user, params: transfer_params)
        if result.failure?
          return render_error("Could not create transfer", status: :unprocessable_entity,
                                                           errors: result.errors)
        end

        head :created
      end

      # PATCH /api/v1/transfers/:id
      # Edits every leg together (see Transfers::UpdateTransfer).
      def update
        result = Transfers::UpdateTransfer.call(user: current_user, legs: @legs, params: transfer_params)
        if result.failure?
          return render_error("Could not update transfer", status: :unprocessable_entity,
                                                           errors: result.errors)
        end

        render_resource(result.data, serializer: TransferSerializer)
      end

      # DELETE /api/v1/transfers/:id
      def destroy
        @legs.each(&:destroy)
        head :no_content
      end

      private

      def listed_legs
        # By transfer_id: an invoice paid in two goes is one payment of two legs.
        payments = current_user.transactions.where(
          id: current_user.transactions.where.not(settled_by_id: nil).select(:settled_by_id)
        ).select(:transfer_id)
        legs = current_user.transactions.transfers.where(credit_card_id: nil).where.not(transfer_id: payments)
        outgoing = legs.where(kind: "expense")
        outgoing.or(legs.where.not(transfer_id: outgoing.select(:transfer_id)))
      end

      def set_legs
        @legs = current_user.transactions.where(transfer_id: params.expect(:id)).order(:id).to_a
        head :not_found if @legs.empty?
      end

      def transfer_params
        params.expect(
          transfer: %i[from_account_id to_account_id amount received_amount date description notes]
        )
      end
    end
  end
end
