module Recurrences
  # Tops a recurrence up to Recurrence::WINDOW months ahead of today.
  #
  # New occurrences copy the latest one still kept, so an edit made to "this
  # and the following" occurrences carries on into the months created later.
  # They start pending, like every future occurrence of a series. Occurrences
  # are only ever added after `extended_through`, so one deleted on its own is
  # never brought back. With no occurrence left to copy, the series is over and
  # the rule goes — and so it does when the next one cannot be created, which
  # means its category, account or card was archived: archiving those ends the
  # entries still repeating on them.
  class Extend < ApplicationService
    COPIED = %w[user_id description kind amount category_id account_id credit_card_id notes series_id].freeze

    # Every rule of `user` (or of everyone) that has fallen behind.
    def self.due(user: nil)
      rules = Recurrence.due
      rules = rules.where(user:) if user
      rules.find_each { |rule| call(rule) }
    end

    def initialize(recurrence)
      @rule = recurrence
    end

    def call
      template = Transaction.where(series_id: @rule.series_id).order(:date, :id).last
      return success(@rule.destroy!) if template.nil?

      created = create_until(Date.current >> Recurrence::WINDOW, template:)
      success(created)
    rescue ActiveRecord::RecordInvalid => e
      @rule.destroy!
      failure(e.record.errors)
    end

    private

    def create_until(horizon, template:)
      created = []
      ApplicationRecord.transaction do
        index = @rule.index_of(@rule.extended_through) + 1
        while (date = @rule.date_at(index)) <= horizon
          created << Transaction.create!(template.attributes.slice(*COPIED).merge("date" => date, "paid" => false))
          index += 1
        end
        @rule.update!(extended_through: created.last.date) if created.any?
      end
      created
    end
  end
end
