# Expense totals per category for a set of transactions, biggest first, with
# subcategories added into their parent (one row per top-level category).
# Each row lists the subcategories behind it, so a chart can drill down;
# `children` is empty when everything sat on the parent itself.
#
# Archived categories still count: their transactions are real spending.
class CategoryBreakdown
  def initialize(transactions)
    @transactions = transactions
  end

  def call
    sums = @transactions.expense.where.not(category_id: nil).group(:category_id).sum(:amount)
    categories = Category.unscoped.where(id: sums.keys).includes(:parent).index_by(&:id)

    sums.group_by { |id, _| top_level(categories[id]) }
        .map { |top, rows| row(top, rows, categories) }
        .sort_by { |row| -row[:total] }
  end

  private

  def top_level(category)
    category.parent || category
  end

  def row(top, rows, categories)
    children = rows.reject { |id, _| id == top.id }.map do |id, total|
      { category_id: id, name: categories[id].name, total: }
    end
    { category_id: top.id, name: top.name, color: top.color, total: rows.sum { |_, total| total },
      children: children.sort_by { |child| -child[:total] } }
  end
end
