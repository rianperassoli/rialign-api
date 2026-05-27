# Helpers to authenticate request specs with a real JWT.
module AuthHelpers
  def auth_headers(user)
    token = JsonWebToken.encode(user_id: user.id)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  def json
    JSON.parse(response.body)
  end
end
