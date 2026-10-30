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
# What counts is what the dashboard counts (see DashboardQuery): settled
# account money and every card charge, transfers and invoice payments left
# out.
class CategoryReportQuery
  BASES = %w[purchase invoice installment].freeze

  # `period` is a date range: its first and last day.
  def initialize(user, period:, basis: "purchase")
    @user = user
    @period = period
    @basis = BASES.include?(basis) ? basis : "purchase"
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
      counted = @user.transactions.non_transfer.in_base_currency.booked
      case @basis
      when "invoice" then counted.reported_between(@period.begin, @period.end)
      when "installment" then counted.between(@period.begin, @period.end)
      else counted.purchased_between(@period.begin, @period.end)
      end
    end
  end
end
