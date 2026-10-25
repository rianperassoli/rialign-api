# Standardized JSON envelope for every endpoint.
#
#   success single:     { "data": { ... } }
#   success collection: { "data": [ ... ], "meta": { pagination } }
#   error:              { "errors": [ "msg", ... ], "message": "..." }
module ApiResponders
  extend ActiveSupport::Concern
  include Pagy::Backend

  private

  def render_resource(resource, serializer:, status: :ok, meta: {})
    render json: { data: serializer.new(resource).as_json, meta: meta }, status: status
  end

  # Paginates `scope` and renders the serialized collection with pagination meta.
  def render_collection(scope, serializer:, status: :ok)
    render_page(scope, status:) { |records| serializer.collection(records) }
  end

  # Same envelope, for a page whose rows are built from the records by the
  # block (e.g. several records per row).
  def render_page(scope, status: :ok)
    opts = params[:items].present? ? { limit: params[:items] } : {}
    pagy, records = pagy(scope, **opts)
    render json: { data: yield(records), meta: { pagination: pagination_meta(pagy) } }, status: status
  end

  def render_error(message, status:, errors: nil)
    render json: { message: message, errors: errors || [message] }, status: status
  end

  def pagination_meta(pagy)
    {
      page: pagy.page,
      items: pagy.limit,
      count: pagy.count,
      pages: pagy.pages,
      next: pagy.next,
      prev: pagy.prev
    }
  end
end
