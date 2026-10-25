module Recurrences
  # Starts a fixed entry with no end date: the first occurrence as submitted
  # (its `paid` flag included), the rule behind it, and the occurrences up to
  # Recurrence::WINDOW months ahead (see Extend).
  class Start < ApplicationService
    def initialize(user:, params:)
      @user = user
      @params = params.to_h.symbolize_keys
    end

    def call
      series_id = SecureRandom.uuid
      first = nil
      ApplicationRecord.transaction do
        first = @user.transactions.create!(@params.merge(series_id:))
        rule = @user.recurrences.create!(series_id:, starts_on: first.date, extended_through: first.date)
        Extend.call(rule)
      end
      success(first)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end
  end
end
