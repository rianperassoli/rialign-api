# Builds a filtered, ordered Transaction relation from request params.
#
# Encapsulating filtering here keeps the controller thin and the logic reusable
# (dashboard, exports, reports). Returns a relation so the caller still controls
# pagination.
#
#   TransactionsQuery.new(current_user.transactions, params).call
class TransactionsQuery
  ALLOWED_SORT = %w[date amount created_at].freeze
  # Organizze's "Tipo" filter. Income and expenses leave transfer legs out
  # (they are money moving, not earning or spending); combined with `paid`
  # they make "receitas recebidas", "transferências não pagas" and so on.
  TYPES = {
    "income" => ->(scope) { scope.non_transfer.income },
    "expense" => ->(scope) { scope.non_transfer.expense },
    "transfer" => ->(scope) { scope.transfers },
    "fixed" => ->(scope) { scope.where.not(series_id: nil).where(installment_number: nil) },
    "installments" => ->(scope) { scope.where.not(installment_number: nil) }
  }.freeze

  def initialize(relation, params = {})
    @relation = relation
    @params = params
  end

  def call
    by_when_and_what(by_where(by_kind(@relation))).order(order_clause)
  end

  private

  # What sort of entry: kind, Organizze's type, settled or not.
  def by_kind(scope)
    scope = scope.where(kind: @params[:kind]) if @params[:kind].present?
    scope = TYPES[@params[:type]].call(scope) if TYPES.key?(@params[:type])
    scope = scope.where(paid: ActiveModel::Type::Boolean.new.cast(@params[:paid])) if @params.key?(:paid)
    scope
  end

  # Where it sits: account, card, category.
  def by_where(scope)
    scope = scope.where(account_id: @params[:account_id]) if @params[:account_id].present?
    scope = scope.where(credit_card_id: @params[:credit_card_id]) if @params[:credit_card_id].present?
    scope = scope.where(category_id: category_ids) if @params[:category_id].present?
    scope
  end

  def by_when_and_what(scope)
    scope = scope.between(parse_date(@params[:from]), parse_date(@params[:to])) if date_range?
    scope = scope.where("description ILIKE ?", "%#{@params[:search]}%") if @params[:search].present?
    scope
  end

  # A category stands for its subcategories too, as in the reports.
  def category_ids
    [@params[:category_id], *Category.unscoped.where(parent_id: @params[:category_id]).pluck(:id)]
  end

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
