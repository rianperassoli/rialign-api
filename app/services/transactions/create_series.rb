module Transactions
  # Materializes a monthly series of transactions in one shot, sharing a
  # `series_id`. Two flavours (mirroring Organizze):
  #
  #  - Installments (`installments: 12`): the submitted amount is the TOTAL
  #    purchase, split into equal monthly legs — any cent remainder lands on
  #    the first leg so the sum always matches. Legs carry
  #    `installment_number`/`installment_total` for "3/12" style display.
  #
  #  - Fixed (`months: 12`): the submitted amount repeats as-is every month
  #    (rent, subscriptions...).
  #
  # Only the first occurrence keeps the submitted `paid` flag; future
  # occurrences are always pending so balances and forecasts stay honest.
  class CreateSeries < ApplicationService
    MAX_OCCURRENCES = 60

    def initialize(user:, params:, installments: nil, months: nil)
      @user = user
      @params = params.to_h.symbolize_keys
      @installments = installments.to_i if installments.present?
      @months = months.to_i if months.present?
    end

    def call
      return failure("Series must have between 2 and #{MAX_OCCURRENCES} occurrences") unless valid_count?

      first_date = Date.parse(@params[:date].to_s)
      series_id = SecureRandom.uuid

      transactions = []
      ApplicationRecord.transaction do
        amounts.each_with_index do |amount, index|
          transactions << @user.transactions.create!(
            leg_attributes(index:, amount:, first_date:, series_id:)
          )
        end
      end
      success(transactions)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    rescue ArgumentError, TypeError
      failure("Amount and date must be valid")
    end

    private

    def count
      @installments || @months || 0
    end

    def installment?
      @installments.present?
    end

    def valid_count?
      count.between?(2, MAX_OCCURRENCES)
    end

    # Installments split the total with the cent remainder on the first leg;
    # fixed series repeat the amount untouched.
    def amounts
      total = BigDecimal(@params[:amount].to_s)
      return Array.new(count, total) unless installment?

      per = (total / count).floor(2)
      [total - (per * (count - 1))] + Array.new(count - 1, per)
    end

    def leg_attributes(index:, amount:, first_date:, series_id:)
      @params.merge(
        amount: amount,
        date: first_date >> index, # Date#>> adds months, clamping short months
        paid: index.zero? && ActiveModel::Type::Boolean.new.cast(@params.fetch(:paid, true)),
        series_id: series_id,
        installment_number: installment? ? index + 1 : nil,
        installment_total: installment? ? count : nil
      )
    end
  end
end
