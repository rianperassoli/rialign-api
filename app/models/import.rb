# One upload of an Organizze export, processed in two background passes.
#
# The export cannot answer everything the app needs — a card's due day and
# limit, which invoice is still open, which accounts stay out of the
# consolidated balance — so reading and writing are separate steps with the
# user in between:
#
#   pending -> analyzing -> awaiting_input -> importing -> completed
#                    \                            \
#                     -> failed                    -> failed
#
# `preview` is what the first pass found (and could infer); `settings` is what
# the user answered. The uploaded file is kept until the write finishes.
class Import < ApplicationRecord
  STATUSES = %w[pending analyzing awaiting_input importing completed failed].freeze

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :filename, :file_path, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def awaiting_input?
    status == "awaiting_input"
  end

  def analyzing!
    update!(status: "analyzing")
  end

  def analyzed!(preview)
    update!(status: "awaiting_input", preview: preview)
  end

  def importing!(settings)
    update!(status: "importing", settings: settings)
  end

  def completed!(report)
    update!(status: "completed", report: report)
    discard_file
  end

  def failed!(message)
    update!(status: "failed", error_message: message)
    discard_file
  end

  private

  # The upload is only needed until the write succeeds; keeping it would leave a
  # copy of the user's whole financial history sitting in tmp.
  def discard_file
    FileUtils.rm_f(file_path)
  end
end
