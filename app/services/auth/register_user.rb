module Auth
  # Creates a user and seeds a default set of categories so a new account is
  # immediately usable on the dashboard.
  class RegisterUser < ApplicationService
    def initialize(params:)
      @params = params
    end

    def call
      user = User.new(@params)

      ActiveRecord::Base.transaction do
        user.save!
        Categories::SeedDefaults.call(user:)
      end

      success(token_payload(user))
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    def token_payload(user)
      { user:, token: JsonWebToken.encode(user_id: user.id) }
    end
  end
end
