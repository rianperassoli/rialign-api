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
    # Transfers and invoice settlements move money around without being real
    # income or expense, so they are excluded from every report figure.
    @scoped ||= @user.transactions.non_transfer.between(@from, @to)
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

  # Includes name/color so the UI can chart categories without extra lookups.
  # Counts paid AND pending expenses: the breakdown answers "where is my money
  # going this month", which includes what is already committed.
  def expense_by_category
    scoped.expense
          .joins(:category)
          .group("categories.id", "categories.name", "categories.color")
          .sum(:amount)
          .map { |(category_id, name, color), total| { category_id:, name:, color:, total: } }
          .sort_by { |row| -row[:total] }
  end
end
