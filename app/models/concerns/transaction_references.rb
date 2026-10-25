# What a transaction points at — its category and its one source (an account
# or a credit card) — and the rules those references follow.
#
# The associations reach archived records on purpose. Category, Account and
# CreditCard hide archived rows by default (SoftDeletable), and through a plain
# belongs_to that hid them from their own history: a transaction on an
# archived category read as uncategorized, failed "category must be present"
# when edited and dropped out of the category charts, and a charge on an
# archived card lost its invoice on the next save.
#
# Archiving still means "do not use any more": a NEW reference to an archived
# record is rejected, while existing entries keep theirs and stay editable.
module TransactionReferences
  extend ActiveSupport::Concern

  REFERENCES = %i[category account credit_card].freeze

  included do
    REFERENCES.each do |name|
      belongs_to name, -> { unscope(where: :archived_at) }, optional: true, inverse_of: :transactions
    end

    validate :exactly_one_source
    validate :category_required
    validate :category_kind_matches
    validate :references_usable
  end

  private

  def exactly_one_source
    sources = [account_id, credit_card_id].compact
    return if sources.size == 1

    errors.add(:base, "must reference exactly one account or credit card")
  end

  # Every regular transaction needs a real category; transfer legs intentionally
  # carry none. Checking the loaded record (not just the id) also rejects a
  # category_id that points to nothing.
  def category_required
    return if transfer? || category.present?

    errors.add(:category, "must be present")
  end

  def category_kind_matches
    return if category.blank? || category.kind == kind

    errors.add(:category, "kind must match the transaction kind")
  end

  # Ids arrive straight from the request, so each reference has to be the
  # user's own — otherwise an entry could be booked on someone else's account
  # and move their balance.
  def references_usable
    REFERENCES.each do |name|
      record = public_send(name)
      next if record.nil?

      if record.user_id != user_id
        errors.add(name, "must belong to the same user")
      elsif record.archived? && (new_record? || attribute_changed?("#{name}_id"))
        errors.add(name, "is archived")
      end
    end
  end
end
