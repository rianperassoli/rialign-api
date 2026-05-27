# Global error handling: maps common exceptions to consistent JSON + status.
# Keeps controllers free of defensive rescue blocks.
module ExceptionHandler
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do |e|
      render_error("Resource not found", status: :not_found, errors: [e.message])
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render_error("Validation failed", status: :unprocessable_entity, errors: e.record.errors.full_messages)
    end

    rescue_from ActionController::ParameterMissing do |e|
      render_error("Missing parameter", status: :bad_request, errors: [e.message])
    end

    rescue_from Pagy::OverflowError do
      render_error("Requested page is out of range", status: :unprocessable_entity)
    end
  end
end
