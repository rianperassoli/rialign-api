# Aggregates a user's financial picture for a given month.
#
# Returns plain hashes (not AR objects) ready for the DashboardSerializer:
#  - totals: income / expense / net for the month (paid only)
#  - forecast: pending income/expense still scheduled in the month
#  - by_category: expense breakdown for charts
class DashboardQuery
  def initialize(user, month: Date.current.beginning_of_month)
    @user = user
    @from = month.beginning_of_month
    @to = month.end_of_month
  end

  def call
    {
      period: { from: @from, to: @to },
      totals: totals,
      forecast: forecast,
      by_category: expense_by_category
    }
  end

  private

  def scoped
    @scoped ||= @user.transactions.between(@from, @to)
  end

  def totals
    paid = scoped.paid
    income = paid.income.sum(:amount)
    expense = paid.expense.sum(:amount)
    { income:, expense:, net: income - expense }
  end

  def forecast
    pending = scoped.pending
    { income: pending.income.sum(:amount), expense: pending.expense.sum(:amount) }
  end

  def expense_by_category
    scoped.expense
          .group(:category_id)
          .sum(:amount)
          .map { |category_id, total| { category_id:, total: } }
          .sort_by { |row| -row[:total] }
  end
end
