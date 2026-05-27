module Api
  module V1
    class AuthenticationController < ApplicationController
      skip_before_action :authenticate_request!, only: %i[register login]

      # POST /api/v1/auth/register
      def register
        result = Auth::RegisterUser.call(params: register_params)
        return render_error("Registration failed", status: :unprocessable_entity, errors: result.errors) if result.failure?

        render_auth(result.data, status: :created)
      end

      # POST /api/v1/auth/login
      def login
        result = Auth::AuthenticateUser.call(email: params[:email], password: params[:password])
        return render_error("Authentication failed", status: :unauthorized, errors: result.errors) if result.failure?

        render_auth(result.data)
      end

      # GET /api/v1/auth/me
      def me
        render_resource(current_user, serializer: UserSerializer)
      end

      private

      def register_params
        params.permit(:name, :email, :password, :password_confirmation)
      end

      def render_auth(data, status: :ok)
        render json: {
          data: {
            token: data[:token],
            user: UserSerializer.new(data[:user]).as_json
          }
        }, status: status
      end
    end
  end
end
