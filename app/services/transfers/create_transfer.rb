module Transfers
  # Moves money between two of a user's bank accounts.
  #
  # A transfer is stored as two linked transactions sharing one `transfer_id`:
  #   - an EXPENSE on the source account
  #   - an INCOME on the destination account
  #
  # Both legs are written in a single DB transaction so a transfer is never left
  # half-recorded. The legs reuse all existing balance math (the expense lowers
  # the source, the income raises the destination, netting to zero across the
  # consolidated balance) but are tagged so reports can exclude them.
  class CreateTransfer < ApplicationService
    def initialize(user:, params:)
      @user = user
      @params = params.to_h.symbolize_keys
    end

    def call
      from = @user.accounts.find_by(id: @params[:from_account_id])
      to   = @user.accounts.find_by(id: @params[:to_account_id])

      return failure("Source account not found") if from.nil?
      return failure("Destination account not found") if to.nil?
      return failure("Source and destination must differ") if from.id == to.id

      transfer_id = SecureRandom.uuid
      ApplicationRecord.transaction do
        build_leg(account: from, kind: "expense", transfer_id:).save!
        build_leg(account: to,   kind: "income",  transfer_id:).save!
      end
      success(transfer_id: transfer_id, from: from, to: to)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    def build_leg(account:, kind:, transfer_id:)
      @user.transactions.new(
        account: account,
        kind: kind,
        transfer_id: transfer_id,
        description: @params[:description].presence || "Transfer",
        amount: @params[:amount],
        date: @params[:date] || Date.current,
        notes: @params[:notes],
        paid: true
      )
    end
  end
end
