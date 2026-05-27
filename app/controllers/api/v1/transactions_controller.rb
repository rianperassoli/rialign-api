module Api
  module V1
    class TransactionsController < ApplicationController
      before_action :set_transaction, only: %i[show update destroy]

      # GET /api/v1/transactions  (filterable + paginated)
      def index
        scope = TransactionsQuery.new(current_user.transactions, filter_params).call
        render_collection(scope, serializer: TransactionSerializer)
      end

      def show
        render_resource(@transaction, serializer: TransactionSerializer)
      end

      # POST /api/v1/transactions
      def create
        result = Transactions::CreateTransaction.call(user: current_user, params: transaction_params)
        if result.failure?
          return render_error("Could not create transaction", status: :unprocessable_entity,
                                                              errors: result.errors)
        end

        render_resource(result.data, serializer: TransactionSerializer, status: :created)
      end

      def update
        @transaction.update!(transaction_params)
        render_resource(@transaction, serializer: TransactionSerializer)
      end

      def destroy
        @transaction.destroy
        head :no_content
      end

      private

      def set_transaction
        @transaction = current_user.transactions.find(params.expect(:id))
      end

      def transaction_params
        params.expect(
          transaction: %i[description kind amount date paid notes
                          category_id account_id credit_card_id]
        )
      end

      def filter_params
        params.permit(:kind, :account_id, :credit_card_id, :category_id,
                      :paid, :from, :to, :search, :sort, :direction).to_h.symbolize_keys
      end
    end
  end
end
