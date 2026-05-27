# Authenticates requests via a Bearer JWT and exposes `current_user`.
module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    return if current_user

    render_error("Unauthorized", status: :unauthorized)
  end

  def current_user
    @current_user ||= begin
      payload = JsonWebToken.decode(bearer_token)
      User.find_by(id: payload[:user_id]) if payload
    end
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.split(" ").last if header.start_with?("Bearer ")
  end
end
