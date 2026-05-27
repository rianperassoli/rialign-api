# Lightweight ownership policy (no Pundit dependency).
#
# Most authorization is already enforced by scoping every query through
# `current_user.association` in controllers. This policy is the explicit,
# auditable check for "does this record belong to the user?" and the seam where
# richer rules (shared accounts, roles) would later live.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def owner?
    record.respond_to?(:user_id) && record.user_id == user&.id
  end

  alias show? owner?
  alias update? owner?
  alias destroy? owner?
end
