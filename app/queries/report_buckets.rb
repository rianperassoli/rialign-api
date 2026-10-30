# A report period cut into days, weeks (from Sunday) or months, or kept
# whole ("total"): the rows of Entradas x Saídas and the columns of the
# categories table. Buckets are clipped to the period, so a week or month
# that starts before it starts with it.
class ReportBuckets
  GROUPS = %w[day week month total].freeze

  attr_reader :group

  delegate :size, to: :ranges

  def initialize(period, group)
    @from = period.begin
    @to = period.end
    @group = GROUPS.include?(group) ? group : "day"
  end

  # [first day, last day] of each bucket, in order.
  def ranges
    @ranges ||= begin
      starts = @group == "total" ? [@from] : (@from..@to).map { |day| start_of(day) }.uniq
      starts.each_with_index.map { |start, index| [start, starts[index + 1] ? starts[index + 1] - 1 : @to] }
    end
  end

  # Which bucket a day falls in; nil outside the period.
  def index_of(day)
    return unless (@from..@to).cover?(day)

    ranges.index { |_, finish| day <= finish }
  end

  private

  def start_of(day)
    start = case @group
            when "week" then day.beginning_of_week(:sunday)
            when "month" then day.beginning_of_month
            else day
            end
    [start, @from].max
  end
end
