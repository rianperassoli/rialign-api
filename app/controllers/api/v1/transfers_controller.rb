module Api
  module V1
    class TransfersController < ApplicationController
      before_action :set_legs, only: %i[show update destroy]

      # GET /api/v1/transfers
      # One row per transfer (its source/expense leg), most recent first.
      def index
        legs = current_user.transactions.transfers.expense.order(date: :desc, id: :desc)
        render_collection(legs, serializer: TransactionSerializer)
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

      def set_legs
        @legs = current_user.transactions.where(transfer_id: params.expect(:id)).order(:id).to_a
        head :not_found if @legs.empty?
      end

      def transfer_params
        params.expect(
          transfer: %i[from_account_id to_account_id amount date description notes]
        )
      end
    end
  end
end
