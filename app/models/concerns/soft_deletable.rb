# Soft delete via an `archived_at` timestamp.
#
# Records are hidden by default (default_scope -> :kept) so the rest of the app
# never has to remember to filter. `destroy` is overridden to archive instead
# of issuing a SQL DELETE, keeping historical financial data intact.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept,     -> { where(archived_at: nil) }
    # Unscope the default `archived_at IS NULL` condition, otherwise it would
    # intersect with this one and always return an empty relation.
    scope :archived, -> { unscope(where: :archived_at).where.not(archived_at: nil) }

    default_scope { kept }
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current) unless archived?
  end

  def restore!
    update!(archived_at: nil)
  end

  # Replace hard delete with soft delete everywhere (controllers, associations).
  def destroy
    archive!
  end
end
