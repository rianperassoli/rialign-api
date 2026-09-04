# Second pass over an upload: writes it, using the settings the user confirmed.
#
# Nothing here raises on a bad file: an import that fails is a normal result the
# user has to see, so the failure is written to the row and the job finishes.
class OrganizzeImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import&.status == "importing"

    run(import)
  end

  private

  def run(import)
    settings = import.settings
    result = Imports::OrganizzeImport.call(
      user: import.user,
      path: import.file_path,
      open_from: parse_month(settings["open_from"]),
      defaults: { credit_cards: settings["credit_cards"] || {}, accounts: settings["accounts"] || {} },
      replace_existing: true
    )

    if result.success?
      import.completed!(result.data)
    else
      import.failed!(result.errors.join(", "))
    end
  rescue StandardError => e
    import.failed!("#{e.class}: #{e.message}")
  end

  # The month the user marked as the first still-open invoice; today's month is
  # the safe fallback, leaving the current cycle open.
  def parse_month(value)
    Date.strptime(value.to_s, "%Y-%m")
  rescue ArgumentError, TypeError
    Date.current.beginning_of_month
  end
end
