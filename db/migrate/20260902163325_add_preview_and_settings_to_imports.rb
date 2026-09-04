class AddPreviewAndSettingsToImports < ActiveRecord::Migration[8.0]
  # An import now pauses between reading the file and writing it: the analysis
  # lands in `preview`, the user answers what the file cannot say, and those
  # answers land in `settings` for the import job to apply.
  def change
    add_column :imports, :preview, :jsonb, null: false, default: {}
    add_column :imports, :settings, :jsonb, null: false, default: {}
  end
end
