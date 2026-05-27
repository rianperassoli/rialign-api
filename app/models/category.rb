# A label for transactions. A category is scoped to a single kind so the
# dashboard can group income vs expense cleanly.
class Category < ApplicationRecord
  include SoftDeletable

  KINDS = %w[income expense].freeze

  belongs_to :user
  has_many :transactions, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
end
