module Auth
  # Changes the password, after checking the current one.
  class ChangePassword < ApplicationService
    def initialize(user:, current_password:, password:, password_confirmation:)
      @user = user
      @current_password = current_password
      @password = password
      @password_confirmation = password_confirmation
    end

    def call
      return failure("Current password is incorrect") unless @user.authenticate(@current_password.to_s)
      return failure("Password can't be blank") if @password.blank?

      if @user.update(password: @password, password_confirmation: @password_confirmation)
        success(@user)
      else
        failure(@user.errors)
      end
    end
  end
end
