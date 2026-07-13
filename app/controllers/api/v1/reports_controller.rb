module Api
  module V1
    class ReportsController < ApplicationController
      DEFAULT_MONTHS = 6

      # GET /api/v1/reports?months=N
      def show
        render json: { data: ReportsQuery.new(current_user, months: months).call }
      end

      private

      def months
        requested = params[:months].to_i
        requested.between?(1, ReportsQuery::MAX_MONTHS) ? requested : DEFAULT_MONTHS
      end
    end
  end
end
