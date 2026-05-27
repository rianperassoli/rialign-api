module Api
  module V1
    class CreditCardsController < ApplicationController
      before_action :set_credit_card, only: %i[show update destroy]

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

      private

      def set_credit_card
        @credit_card = current_user.credit_cards.find(params[:id])
      end

      def credit_card_params
        params.require(:credit_card).permit(:name, :credit_limit, :closing_day, :due_day)
      end
    end
  end
end
