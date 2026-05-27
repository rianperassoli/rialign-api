# Builds a filtered, ordered Transaction relation from request params.
#
# Encapsulating filtering here keeps the controller thin and the logic reusable
# (dashboard, exports, reports). Returns a relation so the caller still controls
# pagination.
#
#   TransactionsQuery.new(current_user.transactions, params).call
class TransactionsQuery
  ALLOWED_SORT = %w[date amount created_at].freeze

  def initialize(relation, params = {})
    @relation = relation
    @params = params
  end

  def call
    scope = @relation
    scope = scope.where(kind: @params[:kind]) if @params[:kind].present?
    scope = scope.where(account_id: @params[:account_id]) if @params[:account_id].present?
    scope = scope.where(credit_card_id: @params[:credit_card_id]) if @params[:credit_card_id].present?
    scope = scope.where(category_id: @params[:category_id]) if @params[:category_id].present?
    scope = scope.where(paid: ActiveModel::Type::Boolean.new.cast(@params[:paid])) if @params.key?(:paid)
    scope = scope.between(parse_date(@params[:from]), parse_date(@params[:to])) if date_range?
    scope = scope.where("description ILIKE ?", "%#{@params[:search]}%") if @params[:search].present?

    scope.order(order_clause)
  end

  private

  def date_range?
    @params[:from].present? && @params[:to].present?
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def order_clause
    column = ALLOWED_SORT.include?(@params[:sort]) ? @params[:sort] : "date"
    direction = @params[:direction] == "asc" ? :asc : :desc
    { column => direction, id: :desc }
  end
end
