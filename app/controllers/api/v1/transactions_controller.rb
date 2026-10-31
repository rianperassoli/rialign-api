module Api
  module V1
    class TransactionsController < ApplicationController
      # Filters an unpaid invoice can never match: it is an expense, still
      # to be paid, with no category and on no single card.
      NOT_INVOICES = { type: %w[income transfer fixed installments], paid: %w[true], kind: %w[income] }.freeze

      before_action :set_transaction, only: %i[show update destroy]

      # GET /api/v1/transactions  (filterable + paginated)
      def index
        transactions = current_user.transactions.includes(:account, category: :parent)
        scope = TransactionsQuery.new(transactions, filter_params).call
        render_collection(scope, serializer: TransactionSerializer,
                                 meta: { totals: totals(scope), open_invoices: open_invoices }.compact)
      end

      def show
        render_resource(@transaction, serializer: TransactionSerializer)
      end

      # POST /api/v1/transactions
      # Top-level `installments: 12` splits the amount into an installment
      # series; `fixed_months: 12` repeats it monthly (see CreateSeries);
      # `fixed: true` without months repeats it with no end (Recurrences::Start).
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

      # PATCH /api/v1/transactions/:id?scope=one|future|series
      # On a series occurrence, `future` and `series` spread the change to the
      # later / all occurrences (see UpdateSeries); `one` is the default.
      def update
        return update_series if @transaction.series_id && Transactions::UpdateSeries::SCOPES.include?(params[:scope])

        @transaction.update!(transaction_params)
        render_resource(@transaction, serializer: TransactionSerializer)
      end

      # DELETE /api/v1/transactions/:id?scope=one|future|series
      # `future` archives this occurrence and the later ones in its series;
      # `series` archives every occurrence. Either keeps the occurrences already
      # paid: that money has moved, and deleting them would rewrite the
      # balance. One alone can still be removed with `one`. A transfer leg
      # takes the whole transfer with it, so no account is left holding half
      # of it.
      # Removing this and the following occurrences, or all of them, also ends
      # an open-ended series, so no new month is created after.
      def destroy
        destroy_targets.each(&:destroy)
        if @transaction.series_id && %w[future series].include?(params[:scope])
          current_user.recurrences.where(series_id: @transaction.series_id).delete_all
        end
        head :no_content
      end

      private

      def update_series
        result = Transactions::UpdateSeries.call(user: current_user, transaction: @transaction,
                                                 params: transaction_params, scope: params[:scope])
        if result.failure?
          return render_error("Could not update transactions", status: :unprocessable_entity,
                                                               errors: result.errors)
        end

        render_resource(result.data, serializer: TransactionSerializer)
      end

      def create_result
        attrs = { user: current_user, params: transaction_params }
        if params[:installments].to_i > 1
          Transactions::CreateSeries.call(**attrs, installments: params[:installments])
        elsif open_ended?
          Recurrences::Start.call(**attrs)
        elsif params[:fixed_months].to_i > 1
          Transactions::CreateSeries.call(**attrs, months: params[:fixed_months])
        else
          Transactions::CreateTransaction.call(**attrs)
        end
      end

      def open_ended?
        ActiveModel::Type::Boolean.new.cast(params[:fixed]) && params[:fixed_months].blank?
      end

      def destroy_targets
        return current_user.transactions.where(transfer_id: @transaction.transfer_id) if @transaction.transfer?
        return [@transaction] if @transaction.series_id.blank?

        series = current_user.transactions.in_series(@transaction.series_id).pending
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
                          category_id account_id credit_card_id invoice_month]
        )
      end

      # What the whole filtered list adds up to, every page of it: Organizze's
      # "Total com o termo …" footer, and the list total. Transfers stay out,
      # invoice payments included, as Organizze adds it up: they only move
      # money, and a payment would count the card purchases a second time
      # (October 2026: 37,32 with them out).
      def totals(scope)
        sums = scope.reorder(nil).non_transfer.group(:kind).sum(:amount)
        income = sums.fetch("income", 0)
        expense = sums.fetch("expense", 0)
        { income:, expense:, net: income - expense }
      end

      # Organizze's cash flow lists the invoices still to be paid among the
      # entries, on their due date. Only when nothing narrows the list to
      # something an invoice is not (a type other than expenses, a category, a
      # card, a search), and only over a period.
      def open_invoices
        filters = filter_params
        return unless filters[:view] == "cash_flow" && !narrowed_past_invoices?(filters)

        period = Date.parse(filters[:from].to_s)..Date.parse(filters[:to].to_s)
        OpenInvoicesQuery.new(current_user, period:, account_id: filters[:account_id].presence).call
      rescue Date::Error
        nil
      end

      def narrowed_past_invoices?(filters)
        %i[category_id credit_card_id search].any? { |key| filters[key].present? } ||
          NOT_INVOICES.any? { |key, values| values.include?(filters[key].to_s) }
      end

      def filter_params
        params.permit(:kind, :type, :view, :account_id, :credit_card_id, :category_id,
                      :paid, :from, :to, :search, :sort, :direction).to_h.symbolize_keys
      end
    end
  end
end
