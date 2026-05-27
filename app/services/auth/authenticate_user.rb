module Auth
  # Verifies credentials and issues a JWT. Returns a generic failure on bad
  # email OR password to avoid leaking which one was wrong.
  class AuthenticateUser < ApplicationService
    def initialize(email:, password:)
      @email = email.to_s.downcase.strip
      @password = password
    end

    def call
      user = User.find_by("lower(email) = ?", @email)

      if user&.authenticate(@password)
        success(user:, token: JsonWebToken.encode(user_id: user.id))
      else
        failure("Invalid email or password")
      end
    end
  end
end
