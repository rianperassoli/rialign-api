module Api
  module V1
    class AccountsController < ApplicationController
      before_action :set_account, only: %i[show update destroy restore]

      # GET /api/v1/accounts
      # `?archived=true` lists the archived ones instead, so they can be
      # reviewed and restored.
      def index
        scope = current_user.accounts
        scope = scope.archived if params[:archived].to_s == "true"
        render_collection(scope.order(:name), serializer: AccountSerializer)
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

      # POST /api/v1/accounts/:id/restore  (unarchive)
      def restore
        @account.restore!
        render_resource(@account, serializer: AccountSerializer)
      end

      private

      # Archived accounts have to be reachable here, otherwise they could never
      # be restored.
      def set_account
        @account = current_user.accounts.unscope(where: :archived_at).find(params.expect(:id))
      end

      def account_params
        params.expect(account: %i[name account_type initial_balance exclude_from_total])
      end
    end
  end
end
