module Transactions
  # Creates a transaction owned by `user`.
  #
  # Why a service and not just `Transaction.create`?
  #  - It builds the record through the user, so ownership is never taken from
  #    the params (references to another user's category/account/card are
  #    rejected by the model, see TransactionReferences).
  #  - It is the single seam where future side effects live (recalculating
  #    cached balances, emitting events, scheduling installments...).
  class CreateTransaction < ApplicationService
    def initialize(user:, params:)
      @user = user
      @params = params.to_h.symbolize_keys
    end

    def call
      transaction = @user.transactions.new(@params)
      transaction.save!
      success(transaction)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end
  end
end
