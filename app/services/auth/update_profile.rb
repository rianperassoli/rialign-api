module Auth
  # Edits the profile. Only the name is editable: the email is the login and
  # stays as registered, so anything else in `params` is ignored.
  class UpdateProfile < ApplicationService
    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      if @user.update(name: @params[:name])
        success(@user)
      else
        failure(@user.errors)
      end
    end
  end
end
