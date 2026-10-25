module Transfers
  # Edits a transfer as a whole: amount, date, description and notes go to
  # every leg, `from_account_id` to the expense (source) leg and
  # `to_account_id` to the income (destination) one, all in one DB transaction
  # so the legs never disagree.
  #
  # An invoice payment is also a transfer leg, but it settled specific charges:
  # changing its amount would no longer match them, so it is undone from the
  # invoice instead (see InvoiceSettlement).
  class UpdateTransfer < ApplicationService
    SHARED = %i[amount date description notes].freeze

    def initialize(user:, legs:, params:)
      @user = user
      @legs = legs
      @params = params.to_h.symbolize_keys
    end

    def call
      return failure("An invoice payment cannot be edited; undo it from the invoice") if invoice_payment?

      accounts = { from: account_for(:from_account_id), to: account_for(:to_account_id) }
      return failure("Account not found") if accounts.value?(:missing)
      return failure("Source and destination must differ") if same_account?(**accounts)

      ApplicationRecord.transaction do
        @legs.each { |leg| apply(leg, account: leg.income? ? accounts[:to] : accounts[:from]) }
      end
      success(@legs)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    def invoice_payment?
      @legs.any? { |leg| leg.settled_charges.exists? }
    end

    # nil when the param is absent (keep the leg's account), :missing when it
    # names no account of this user.
    def account_for(key)
      return nil if @params[key].blank?

      @user.accounts.find_by(id: @params[key]) || :missing
    end

    def apply(leg, account:)
      leg.assign_attributes(@params.slice(*SHARED))
      leg.account = account if account
      leg.editing_as_pair = true
      leg.save!
    end

    # Only a paired transfer has two sides to compare; each side keeps its
    # account unless a new one is given.
    def same_account?(from:, to:)
      source = @legs.find { |leg| !leg.income? }
      destination = @legs.find(&:income?)
      return false unless source && destination

      account_id_after(source, from) == account_id_after(destination, to)
    end

    def account_id_after(leg, account)
      account ? account.id : leg.account_id
    end
  end
end
