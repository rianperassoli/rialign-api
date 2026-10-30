# Organizze's "Categorias" report: what each category took (expenses) and
# brought in (income) over a period, biggest first, with subcategories added
# into their parent (see CategoryBreakdown).
#
# Account entries count on their date. Card charges count by `basis`, the
# report's "Gastos de cartão com base na":
#  - "purchase" (default): the purchase date, an installment once, by its
#    first parcel (Transaction.purchased_between);
#  - "invoice": the month the charge's invoice is due;
#  - "installment": each parcel on its own date, so a month holds the parcel
#    that falls in it.
#
# Transfers and invoice payments are left out. Everything else counts,
# settled or not, unless the report's filters narrow it down, as Organizze's
# "Filtros" do:
#  - `category_ids`: those categories, a parent bringing its subcategories;
#  - `account_ids` / `credit_card_ids`: entries on those accounts and cards;
#  - `status`: "paid" or "unpaid" only.
class CategoryReportQuery
  BASES = %w[purchase invoice installment].freeze
  STATUSES = %w[paid unpaid].freeze

  # `period` is a date range: its first and last day.
  def initialize(user, period:, basis: "purchase", filters: {})
    @user = user
    @period = period
    @basis = BASES.include?(basis) ? basis : "purchase"
    @filters = filters
  end

  def call
    {
      period: { from: @period.begin, to: @period.end },
      basis: @basis,
      expense: CategoryBreakdown.new(scoped, kind: "expense").call,
      income: CategoryBreakdown.new(scoped, kind: "income").call
    }
  end

  private

  def scoped
    @scoped ||= begin
      counted = filtered(@user.transactions.non_transfer.in_base_currency)
      case @basis
      when "invoice" then counted.reported_between(@period.begin, @period.end)
      when "installment" then counted.between(@period.begin, @period.end)
      else counted.purchased_between(@period.begin, @period.end)
      end
    end
  end

  def filtered(scope)
    scope = scope.where(category_id: categories) if @filters[:category_ids].present?
    scope = scope.where(paid: @filters[:status] == "paid") if STATUSES.include?(@filters[:status])
    return scope if @filters[:account_ids].blank? && @filters[:credit_card_ids].blank?

    scope.where(account_id: @filters[:account_ids]).or(scope.where(credit_card_id: @filters[:credit_card_ids]))
  end

  def categories
    ids = @filters[:category_ids]
    Category.unscoped.where(user: @user).where(id: ids).or(Category.unscoped.where(user: @user, parent_id: ids))
            .select(:id)
  end
end
