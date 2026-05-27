module Api
  module V1
    class CategoriesController < ApplicationController
      before_action :set_category, only: %i[show update destroy]

      def index
        scope = current_user.categories.order(:kind, :name)
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        render_collection(scope, serializer: CategorySerializer)
      end

      def show
        render_resource(@category, serializer: CategorySerializer)
      end

      def create
        category = current_user.categories.new(category_params)
        category.save!
        render_resource(category, serializer: CategorySerializer, status: :created)
      end

      def update
        @category.update!(category_params)
        render_resource(@category, serializer: CategorySerializer)
      end

      def destroy
        @category.destroy
        head :no_content
      end

      private

      def set_category
        @category = current_user.categories.find(params.expect(:id))
      end

      def category_params
        params.expect(category: %i[name kind color])
      end
    end
  end
end
