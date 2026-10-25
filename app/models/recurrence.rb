# The rule behind a fixed entry with no end date (Organizze's "fixa" without a
# number of months).
#
# The occurrences are ordinary transactions sharing `series_id` — so balances,
# reports, edits and deletes by scope all work on real rows — and this record
# only keeps the series created WINDOW months ahead: `starts_on` gives the day
# of the month, `extended_through` the last occurrence created so far. Removing
# the rule ends the series; the occurrences already created stay.
class Recurrence < ApplicationRecord
  WINDOW = 12

  belongs_to :user

  validates :series_id, :starts_on, :extended_through, presence: true

  # Rules that have fallen behind the window and need more occurrences.
  scope :due, -> { where(extended_through: ...(Date.current >> (WINDOW - 1))) }

  # The occurrence date `index` months after the first, clamped on short
  # months the same way CreateSeries does (Date#>>).
  def date_at(index)
    starts_on >> index
  end

  # How many months after the first `date` falls.
  def index_of(date)
    ((date.year * 12) + date.month) - ((starts_on.year * 12) + starts_on.month)
  end
end
