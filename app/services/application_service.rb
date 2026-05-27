# Base class for Service Objects.
#
# Services encapsulate a single business operation and always return a
# `ApplicationService::Result`, so callers (controllers, jobs, other services)
# branch on `result.success?` instead of rescuing exceptions for control flow.
#
#   result = Transactions::CreateTransaction.call(user:, params:)
#   if result.success?
#     render_resource result.data
#   else
#     render_errors result.errors
#   end
class ApplicationService
  Result = Struct.new(:success, :data, :errors, keyword_init: true) do
    def success? = success
    def failure? = !success
  end

  def self.call(...)
    new(...).call
  end

  private

  def success(data = nil)
    Result.new(success: true, data:, errors: [])
  end

  # Accepts a String, Array, or an ActiveModel::Errors instance.
  def failure(errors)
    list =
      case errors
      when ActiveModel::Errors then errors.full_messages
      else Array(errors)
      end
    Result.new(success: false, data: nil, errors: list)
  end
end
