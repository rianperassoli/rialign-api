module Api
  module V1
    class DashboardController < ApplicationController
      # GET /api/v1/dashboard?month=YYYY-MM
      def show
        summary = DashboardQuery.new(current_user, month: month).call
        balances = Accounts::BalanceCalculator.call(user: current_user).data

        render json: {
          data: DashboardSerializer.new(summary, balances: balances).as_json
        }
      end

      # GET /api/v1/dashboard/balances  (consolidated balance + per-account)
      def balances
        result = Accounts::BalanceCalculator.call(user: current_user).data

        render json: {
          data: {
            consolidated_balance: result[:consolidated_balance],
            accounts: result[:accounts].map { |r| AccountSerializer.new(r[:account], balance: r[:balance]).as_json },
            credit_cards: result[:credit_cards].map do |r|
              CreditCardSerializer.new(r[:credit_card], open_invoice: r[:open_invoice],
                                                        next_invoice: r[:next_invoice],
                                                        available_limit: r[:available_limit]).as_json
            end
          }
        }
      end

      private

      def month
        return Date.current.beginning_of_month if params[:month].blank?

        Date.strptime(params[:month], "%Y-%m").beginning_of_month
      rescue ArgumentError
        Date.current.beginning_of_month
      end
    end
  end
end
