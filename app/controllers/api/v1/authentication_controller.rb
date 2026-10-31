module Api
  module V1
    class AuthenticationController < ApplicationController
      skip_before_action :authenticate_request!, only: %i[register login]

      # POST /api/v1/auth/register
      def register
        result = Auth::RegisterUser.call(params: register_params)
        if result.failure?
          return render_error("Registration failed", status: :unprocessable_entity,
                                                     errors: result.errors)
        end

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

      # PATCH /api/v1/auth/me — the name only; the email can't be changed.
      def update
        result = Auth::UpdateProfile.call(user: current_user, params: params)
        return render_error("Update failed", status: :unprocessable_entity, errors: result.errors) if result.failure?

        render_resource(result.data, serializer: UserSerializer)
      end

      # PATCH /api/v1/auth/password
      def change_password
        result = Auth::ChangePassword.call(
          user: current_user,
          current_password: params[:current_password],
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )
        if result.failure?
          return render_error("Password change failed", status: :unprocessable_entity,
                                                        errors: result.errors)
        end

        render_resource(result.data, serializer: UserSerializer)
      end

      # DELETE /api/v1/auth/me — permanent; needs the password in the body.
      def destroy
        result = Auth::DeleteAccount.call(user: current_user, password: params[:password])
        if result.failure?
          return render_error("Account deletion failed", status: :unprocessable_entity,
                                                         errors: result.errors)
        end

        head :no_content
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
