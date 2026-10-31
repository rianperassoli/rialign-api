# A label for transactions. A category is scoped to a single kind so the
# dashboard can group income vs expense cleanly.
#
# A category can sit under another one, one level deep (Organizze's
# subcategories): the parent is a top-level category of the same user and kind.
# Reports add a subcategory into its parent (see CategoryBreakdown).
class Category < ApplicationRecord
  include SoftDeletable

  KINDS = %w[income expense].freeze

  belongs_to :user
  # Reaches an archived parent too, so a subcategory still names where it sat.
  belongs_to :parent, -> { unscope(where: :archived_at) },
             class_name: "Category", optional: true, inverse_of: :subcategories
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, inverse_of: :parent,
                           dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error

  scope :top_level, -> { where(parent_id: nil) }

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  # A name from the web app's icon set ("shopping-cart"); the app draws it.
  validates :icon, format: { with: /\A[a-z0-9-]{1,40}\z/ }, allow_blank: true
  validate :parent_usable
  validate :kind_kept_once_used, on: :update

  # Archiving a category takes its subcategories with it, as in Organizze.
  def archive!
    return super if archived?

    self.class.transaction do
      subcategories.each(&:archive!)
      super
    end
  end

  # What a subcategory shows when it has no color of its own.
  def display_color
    color.presence || parent&.color
  end

  # Likewise for the icon.
  def display_icon
    icon.presence || parent&.icon
  end

  private

  def parent_usable
    return if parent.nil?

    error = hierarchy_error || compatibility_error
    errors.add(:parent, error) if error
  end

  # Keeps the tree one level deep.
  def hierarchy_error
    return "cannot be the category itself" if parent_id == id
    return "must be a top-level category" if parent.parent_id.present?

    "cannot have subcategories of its own" if subcategories.exists?
  end

  # Category#kind must match every transaction on it and every subcategory
  # under it, archived ones included; changing it would leave expenses filed
  # under an income category. A new category of the other kind is the way.
  def kind_kept_once_used
    return unless kind_changed?
    return unless Transaction.unscoped.exists?(category_id: id) || Category.unscoped.exists?(parent_id: id)

    errors.add(:kind, "cannot change once the category is in use")
  end

  def compatibility_error
    return "must belong to the same user" if parent.user_id != user_id
    return "must be of the same kind" if parent.kind != kind

    "is archived" if parent.archived? && (new_record? || parent_id_changed?)
  end
end
