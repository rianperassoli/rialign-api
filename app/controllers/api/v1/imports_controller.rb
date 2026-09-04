module Api
  module V1
    # Upload an Organizze .xls export and follow the background job that loads
    # it. `create` only stores the file and enqueues; the client polls `show`.
    class ImportsController < ApplicationController
      MAX_BYTES = 20.megabytes
      ALLOWED_EXTENSIONS = %w[.xls .xlsx].freeze

      # GET /api/v1/imports
      def index
        render_collection(current_user.imports.recent, serializer: ImportSerializer)
      end

      # GET /api/v1/imports/:id
      def show
        import = current_user.imports.find(params.expect(:id))
        render_resource(import, serializer: ImportSerializer)
      end

      # POST /api/v1/imports
      def create
        file = params[:file]
        error = validation_error(file)
        return render_error(error, status: :unprocessable_entity) if error

        import = current_user.imports.create!(filename: file.original_filename, file_path: store(file))
        AnalyzeImportJob.perform_later(import.id)
        render_resource(import, serializer: ImportSerializer, status: :accepted)
      end

      # POST /api/v1/imports/:id/confirm
      # Answers the questions the export cannot, then starts the write.
      def confirm
        import = current_user.imports.find(params.expect(:id))
        unless import.awaiting_input?
          return render_error("This import is not waiting for confirmation", status: :unprocessable_entity)
        end

        import.importing!(settings_params)
        OrganizzeImportJob.perform_later(import.id)
        render_resource(import, serializer: ImportSerializer, status: :accepted)
      end

      private

      # Names come from the uploaded file, so the per-account and per-card keys
      # cannot be declared up front — only the leaf attributes are constrained.
      def settings_params
        raw = params.fetch(:settings, {}).permit!.to_h
        {
          "open_from" => raw["open_from"],
          "accounts" => scoped(raw["accounts"], %w[exclude_from_total]),
          "credit_cards" => scoped(raw["credit_cards"], %w[closing_day due_day credit_limit])
        }
      end

      def scoped(entries, allowed)
        (entries || {}).transform_values { |values| values.to_h.slice(*allowed) }
      end

      def validation_error(file)
        return "No file was uploaded" unless file.respond_to?(:original_filename)
        return "File is too large (max #{MAX_BYTES / 1.megabyte}MB)" if file.size > MAX_BYTES

        extension = File.extname(file.original_filename).downcase
        "Unsupported file type: #{extension.presence || "none"}" unless ALLOWED_EXTENSIONS.include?(extension)
      end

      # Kept outside the upload's own tempfile, which Rack removes as soon as the
      # request ends — the job runs after that. Scoped per environment so a test
      # run cannot sweep away a real pending upload.
      def store(file)
        dir = Rails.root.join("tmp/imports", Rails.env)
        FileUtils.mkdir_p(dir)
        path = dir.join("#{SecureRandom.uuid}#{File.extname(file.original_filename).downcase}")
        File.binwrite(path, file.read)
        path.to_s
      end
    end
  end
end
