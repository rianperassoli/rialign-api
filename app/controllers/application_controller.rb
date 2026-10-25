class ApplicationController < ActionController::API
  include ApiResponders
  include ExceptionHandler
  include JwtAuthenticatable

  # Open-ended fixed entries are kept 12 months ahead. There is no scheduler,
  # so the user's own requests do it: one indexed query when nothing is due
  # (`rake recurrences:extend` does the same for everyone, for a cron).
  before_action :extend_recurrences

  private

  def extend_recurrences
    Recurrences::Extend.due(user: current_user) if current_user
  end
end
