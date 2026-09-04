class ImportSerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      status: object.status,
      filename: object.filename,
      preview: object.preview,
      report: object.report,
      error_message: object.error_message,
      created_at: object.created_at
    }
  end
end
