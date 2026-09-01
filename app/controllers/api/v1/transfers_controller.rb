module Api
  module V1
    class TransfersController < ApplicationController
      # GET /api/v1/transfers
      # One row per transfer (its source/expense leg), most recent first.
      def index
        legs = current_user.transactions.transfers.expense.order(date: :desc, id: :desc)
        render_collection(legs, serializer: TransactionSerializer)
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

      # DELETE /api/v1/transfers/:id   (:id is the shared transfer_id)
      # Editing a transfer is delete + recreate, so both legs are removed here.
      def destroy
        legs = current_user.transactions.where(transfer_id: params.expect(:id))
        return head :not_found if legs.empty?

        legs.each(&:destroy)
        head :no_content
      end

      private

      def transfer_params
        params.expect(
          transfer: %i[from_account_id to_account_id amount date description notes]
        )
      end
    end
  end
end
