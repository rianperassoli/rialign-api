module Transactions
  # Creates a transaction owned by `user`.
  #
  # Why a service and not just `Transaction.create`?
  #  - It resolves & authorizes the category/account/credit_card against the
  #    current user (preventing cross-user references).
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
    rescue ActiveRecord::RecordNotFound
      failure("Referenced category, account or credit card was not found")
    end
  end
end
