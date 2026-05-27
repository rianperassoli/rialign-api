module Api
  module V1
    class AccountsController < ApplicationController
      before_action :set_account, only: %i[show update destroy]

      # GET /api/v1/accounts
      def index
        scope = current_user.accounts.order(:name)
        render_collection(scope, serializer: AccountSerializer)
      end

      # GET /api/v1/accounts/:id
      def show
        render_resource(@account, serializer: AccountSerializer)
      end

      # POST /api/v1/accounts
      def create
        account = current_user.accounts.new(account_params)
        account.save!
        render_resource(account, serializer: AccountSerializer, status: :created)
      end

      # PATCH/PUT /api/v1/accounts/:id
      def update
        @account.update!(account_params)
        render_resource(@account, serializer: AccountSerializer)
      end

      # DELETE /api/v1/accounts/:id  (soft delete)
      def destroy
        @account.destroy
        head :no_content
      end

      private

      def set_account
        @account = current_user.accounts.find(params.expect(:id))
      end

      def account_params
        params.expect(account: %i[name account_type initial_balance])
      end
    end
  end
end
