# First pass over an upload: read it, write nothing, and park the import waiting
# for the answers the file cannot give.
class AnalyzeImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import&.status == "pending"

    run(import)
  end

  private

  def run(import)
    import.analyzing!
    result = Imports::AnalyzeOrganizzeExport.call(path: import.file_path)

    if result.success?
      import.analyzed!(result.data)
    else
      import.failed!(result.errors.join(", "))
    end
  rescue StandardError => e
    import.failed!("#{e.class}: #{e.message}")
  end
end
