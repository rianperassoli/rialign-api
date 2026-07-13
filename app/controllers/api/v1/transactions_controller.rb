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
      # Top-level `installments: 12` splits the amount into an installment
      # series; `fixed_months: 12` repeats it monthly (see CreateSeries).
      def create
        result = create_result
        if result.failure?
          return render_error("Could not create transaction", status: :unprocessable_entity,
                                                              errors: result.errors)
        end

        first = Array(result.data).first
        meta = result.data.is_a?(Array) ? { series_count: result.data.size } : {}
        render_resource(first, serializer: TransactionSerializer, status: :created, meta: meta)
      end

      def update
        @transaction.update!(transaction_params)
        render_resource(@transaction, serializer: TransactionSerializer)
      end

      # DELETE /api/v1/transactions/:id?scope=one|future|series
      # `future` archives this occurrence and the later ones in its series;
      # `series` archives every occurrence.
      def destroy
        destroy_targets.each(&:destroy)
        head :no_content
      end

      private

      def create_result
        if params[:installments].to_i > 1
          Transactions::CreateSeries.call(user: current_user, params: transaction_params,
                                          installments: params[:installments])
        elsif params[:fixed_months].to_i > 1
          Transactions::CreateSeries.call(user: current_user, params: transaction_params,
                                          months: params[:fixed_months])
        else
          Transactions::CreateTransaction.call(user: current_user, params: transaction_params)
        end
      end

      def destroy_targets
        return [@transaction] if @transaction.series_id.blank?

        series = current_user.transactions.in_series(@transaction.series_id)
        case params[:scope]
        when "series" then series
        when "future" then series.where(date: @transaction.date..)
        else [@transaction]
        end
      end

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
