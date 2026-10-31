module Auth
  # Permanently deletes the user and everything that belongs to them, after
  # checking the password. Archiving (SoftDeletable) is not enough here: the
  # rows are removed for real, children before parents, in one transaction, so
  # nothing is left behind and a failure leaves the account untouched.
  class DeleteAccount < ApplicationService
    def initialize(user:, password:)
      @user = user
      @password = password
    end

    def call
      return failure("Password is incorrect") unless @user.authenticate(@password.to_s)

      ActiveRecord::Base.transaction do
        [Transaction, Recurrence, Import, CreditCard, Account, Category].each do |model|
          model.unscoped.where(user_id: @user.id).delete_all
        end
        @user.delete
      end

      success
    end
  end
end
