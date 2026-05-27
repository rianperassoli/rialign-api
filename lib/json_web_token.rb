# Thin wrapper around the `jwt` gem. Centralizes signing key, algorithm and
# default expiry so controllers/services never touch raw JWT internals.
module JsonWebToken
  module_function

  ALGORITHM = "HS256".freeze
  DEFAULT_EXP = 24.hours

  # Falls back to a dev key, but production MUST set JWT_SECRET_KEY.
  def secret_key
    ENV.fetch("JWT_SECRET_KEY") { Rails.application.secret_key_base }
  end

  def encode(payload, exp: DEFAULT_EXP.from_now)
    payload = payload.dup
    payload[:exp] = exp.to_i
    JWT.encode(payload, secret_key, ALGORITHM)
  end

  # Returns a HashWithIndifferentAccess or nil when invalid/expired.
  def decode(token)
    decoded, = JWT.decode(token, secret_key, true, algorithm: ALGORITHM)
    ActiveSupport::HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
