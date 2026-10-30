module Api
  module V1
    class ReportsController < ApplicationController
      # A daily report over more than this would be thousands of rows.
      MAX_DAYS = 366 * 5

      # GET /api/v1/reports/cash_flow?from=&to=&group=day|week|month|total&unpaid=1&account_id=
      # The period defaults to the current month.
      def cash_flow
        account = current_user.accounts.find(params.expect(:account_id)) if params[:account_id].present?
        data = CashFlowQuery.new(current_user, period:, group: params[:group].to_s,
                                               unpaid: ActiveModel::Type::Boolean.new.cast(params[:unpaid]),
                                               account:).call
        render json: { data: }
      end

      # GET /api/v1/reports/categories?from=&to=&basis=purchase|invoice|installment
      #   &category_ids=1,2&account_ids=3&credit_card_ids=4&status=paid|unpaid
      def categories
        render json: { data: CategoryReportQuery.new(current_user, period:, basis: params[:basis].to_s,
                                                                   filters: category_filters).call }
      end

      private

      # The days between the "YYYY-MM-DD" params, in order and capped at MAX_DAYS.
      def period
        from = parse_date(params[:from]) || Date.current.beginning_of_month
        to = parse_date(params[:to]) || from.end_of_month
        from, to = to, from if to < from
        from..[to, from + MAX_DAYS].min
      end

      # Lists arrive comma-separated ("1,2,3"); anything that is not an id drops out.
      def category_filters
        lists = %i[category_ids account_ids credit_card_ids].index_with do |key|
          params[key].to_s.split(",").map(&:to_i).select(&:positive?)
        end
        lists.merge(status: params[:status].to_s)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
