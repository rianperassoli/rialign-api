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
#
# Given a `group` (day, week or month), each category also gets its total
# per bucket — Organizze's lines view and the table under it.
class CategoryReportQuery
  BASES = %w[purchase invoice installment].freeze
  STATUSES = %w[paid unpaid].freeze

  # `period` is a date range: its first and last day.
  def initialize(user, period:, basis: "purchase", filters: {}, group: nil)
    @user = user
    @period = period
    @basis = BASES.include?(basis) ? basis : "purchase"
    @filters = filters
    @buckets = ReportBuckets.new(period, group) if group.present?
  end

  def call
    result = {
      period: { from: @period.begin, to: @period.end },
      basis: @basis,
      expense: CategoryBreakdown.new(scoped, kind: "expense").call,
      income: CategoryBreakdown.new(scoped, kind: "income").call
    }
    result[:series] = series if @buckets
    result
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

  def series
    {
      group: @buckets.group,
      buckets: @buckets.ranges.map { |from, to| { from:, to: } },
      expense: series_for("expense"),
      income: series_for("income")
    }
  end

  # One row per top-level category (subcategories added in), its total per
  # bucket, biggest overall first. A card charge falls on the day its basis
  # says: the first of its invoice's month when it is placed by invoice.
  def series_for(kind)
    day = @basis == "invoice" ? Transaction::REPORT_DATE : :date
    sums = scoped.where(kind:).where.not(category_id: nil).group(:category_id, day).sum(:amount)
    categories = Category.unscoped.where(id: sums.keys.map(&:first)).includes(:parent).index_by(&:id)
    rows = Hash.new { |hash, top| hash[top] = Array.new(@buckets.size, 0) }
    # The scope only holds days inside the period, so every one has a bucket.
    sums.each do |(id, date), total|
      rows[categories[id].parent || categories[id]][@buckets.index_of(date.to_date)] += total
    end
    rows.map { |top, values| { category_id: top.id, name: top.name, color: top.color, icon: top.icon, values: } }
        .sort_by { |row| -row[:values].sum }
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
