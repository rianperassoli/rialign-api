# Aggregates historical figures for the reports screen:
#   - monthly: paid income/expense/net for each of the last `months` months
#     (every month is present, zero-filled, so charts get a continuous axis)
#   - by_category: paid expense totals per category over the same window
#
# Transfers and invoice settlements are excluded, like every other report
# (see Transaction#non_transfer).
class ReportsQuery
  MAX_MONTHS = 24

  def initialize(user, months: 6, upto: Date.current)
    @user = user
    @months = months.clamp(1, MAX_MONTHS)
    @to = upto.end_of_month
    @from = (upto << (@months - 1)).beginning_of_month
  end

  def call
    {
      period: { from: @from, to: @to },
      monthly: monthly,
      by_category: by_category
    }
  end

  private

  def scoped
    @scoped ||= @user.transactions.non_transfer.paid.between(@from, @to)
  end

  def monthly
    sums = scoped.group(Arel.sql("to_char(date, 'YYYY-MM')"), :kind).sum(:amount)

    (0...@months).map do |offset|
      key = (@from >> offset).strftime("%Y-%m")
      income  = sums.fetch([key, "income"], 0)
      expense = sums.fetch([key, "expense"], 0)
      { month: key, income:, expense:, net: income - expense }
    end
  end

  def by_category
    scoped.expense
          .joins(:category)
          .group("categories.id", "categories.name", "categories.color")
          .sum(:amount)
          .map { |(category_id, name, color), total| { category_id:, name:, color:, total: } }
          .sort_by { |row| -row[:total] }
  end
end
