module Api
  module V1
    class CreditCardsController < ApplicationController
      before_action :set_credit_card, only: %i[show update destroy pay_invoice invoice]

      def index
        scope = current_user.credit_cards.order(:name)
        render_collection(scope, serializer: CreditCardSerializer)
      end

      def show
        render_resource(@credit_card, serializer: CreditCardSerializer)
      end

      def create
        card = current_user.credit_cards.new(credit_card_params)
        card.save!
        render_resource(card, serializer: CreditCardSerializer, status: :created)
      end

      def update
        @credit_card.update!(credit_card_params)
        render_resource(@credit_card, serializer: CreditCardSerializer)
      end

      def destroy
        @credit_card.destroy
        head :no_content
      end

      # GET /api/v1/credit_cards/:id/invoice?month=YYYY-MM
      # The monthly invoice: cycle period, closing/due dates, totals and the
      # charges inside the cycle (see CreditCardInvoiceQuery).
      def invoice
        result = CreditCardInvoiceQuery.new(@credit_card, month: invoice_month).call

        render json: {
          data: result.merge(transactions: TransactionSerializer.collection(result[:transactions]))
        }
      end

      # POST /api/v1/credit_cards/:id/pay_invoice
      def pay_invoice
        result = CreditCards::PayInvoice.call(
          user: current_user, credit_card: @credit_card, params: pay_invoice_params
        )
        if result.failure?
          return render_error("Could not pay invoice", status: :unprocessable_entity,
                                                       errors: result.errors)
        end

        render_resource(result.data[:transaction], serializer: TransactionSerializer, status: :created)
      end

      private

      def set_credit_card
        @credit_card = current_user.credit_cards.find(params.expect(:id))
      end

      def credit_card_params
        params.expect(credit_card: %i[name credit_limit closing_day due_day payment_account_id])
      end

      def pay_invoice_params
        return {} unless params.key?(:payment)

        params.expect(payment: %i[account_id date month])
      end

      def invoice_month
        return Date.current.beginning_of_month if params[:month].blank?

        Date.strptime(params[:month], "%Y-%m").beginning_of_month
      rescue ArgumentError
        Date.current.beginning_of_month
      end
    end
  end
end
