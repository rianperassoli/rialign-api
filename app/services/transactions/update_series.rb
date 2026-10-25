module Transactions
  # Edits one occurrence of a series (installments or a fixed entry) and
  # spreads the change to its siblings, mirroring Organizze's "this one / this
  # and the next ones / all":
  #
  #   scope "future" - this occurrence and the later ones
  #   scope "series" - every occurrence
  #
  # The edited occurrence takes every change. The others take what describes
  # the entry — description, category, notes, and while still pending also the
  # amount, kind and source — but keep their own date, paid flag and invoice:
  # those belong to each month. An occurrence already paid keeps its amount
  # and source too, so a settled month or a paid invoice never changes under
  # it.
  class UpdateSeries < ApplicationService
    SCOPES = %w[future series].freeze
    PER_OCCURRENCE = %i[date paid invoice_month].freeze
    DESCRIPTIVE = %i[description category_id notes].freeze

    def initialize(user:, transaction:, params:, scope:)
      @user = user
      @transaction = transaction
      @params = params.to_h.symbolize_keys
      @scope = scope
    end

    def call
      ApplicationRecord.transaction do
        # Read before the update: "the later ones" are later than where this
        # occurrence was, even if its own date is being changed.
        targets = siblings(from: @transaction.date)
        @transaction.update!(@params)
        targets.each { |sibling| sibling.update!(shared_for(sibling)) }
      end
      success(@transaction)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    def siblings(from:)
      series = @user.transactions.in_series(@transaction.series_id).where.not(id: @transaction.id)
      series = series.where(date: from..) if @scope == "future"
      series.order(:date, :id).to_a
    end

    def shared_for(sibling)
      shared = @params.except(*PER_OCCURRENCE)
      sibling.paid? ? shared.slice(*DESCRIPTIVE) : shared
    end
  end
end
