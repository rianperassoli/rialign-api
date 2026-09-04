require "rails_helper"

RSpec.describe "Api::V1::Imports", type: :request do
  let(:user) { create(:user) }

  # A request only stores the file; the job that would discard it does not run
  # here, so the spec cleans up after itself.
  after { FileUtils.rm_rf(Rails.root.join("tmp/imports", Rails.env)) }

  def upload(name: "movimentacoes.xls", content: "binary")
    file = Tempfile.new([File.basename(name, ".*"), File.extname(name)])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel", original_filename: name)
  end

  describe "POST /api/v1/imports" do
    it "stores the upload, enqueues the analysis and answers 202" do
      expect do
        post "/api/v1/imports", params: { file: upload }, headers: auth_headers(user).except("Content-Type")
      end.to have_enqueued_job(AnalyzeImportJob)

      expect(response).to have_http_status(:accepted)
      expect(json.dig("data", "status")).to eq("pending")
      expect(json.dig("data", "filename")).to eq("movimentacoes.xls")
    end

    # The upload's own tempfile is gone by the time the job runs, so the file has
    # to survive the request.
    it "keeps the uploaded file readable after the request" do
      post "/api/v1/imports", params: { file: upload(content: "payload") },
                              headers: auth_headers(user).except("Content-Type")

      import = Import.find(json.dig("data", "id"))
      expect(File.read(import.file_path)).to eq("payload")
    end

    it "rejects a file type it cannot read" do
      post "/api/v1/imports", params: { file: upload(name: "extrato.pdf") },
                              headers: auth_headers(user).except("Content-Type")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["message"]).to match(/Unsupported file type/)
    end

    it "rejects a request with no file" do
      post "/api/v1/imports", params: {}, headers: auth_headers(user).except("Content-Type")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["message"]).to match(/No file/)
    end

    it "rejects a file over the size limit" do
      stub_const("Api::V1::ImportsController::MAX_BYTES", 4)
      post "/api/v1/imports", params: { file: upload(content: "far too long") },
                              headers: auth_headers(user).except("Content-Type")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["message"]).to match(/too large/)
    end
  end

  describe "POST /api/v1/imports/:id/confirm" do
    let(:import) { create(:import, user:, status: "awaiting_input") }

    it "stores the answers and starts the write" do
      settings = {
        open_from: "2026-10",
        accounts: { "Lifetycon" => { exclude_from_total: true } },
        credit_cards: { "NuBank - Cartão" => { closing_day: 31, due_day: 10, credit_limit: "7207.80" } }
      }

      expect do
        post "/api/v1/imports/#{import.id}/confirm", params: { settings: }.to_json, headers: auth_headers(user)
      end.to have_enqueued_job(OrganizzeImportJob)

      expect(response).to have_http_status(:accepted)
      expect(import.reload.status).to eq("importing")
      expect(import.settings.dig("credit_cards", "NuBank - Cartão", "due_day")).to eq(10)
      expect(import.settings.dig("accounts", "Lifetycon", "exclude_from_total")).to be(true)
    end

    # Names come from the file, so only the leaf attributes can be constrained.
    it "drops attributes that are not part of the settings" do
      settings = { credit_cards: { "NuBank - Cartão" => { due_day: 10, user_id: 999 } } }

      post "/api/v1/imports/#{import.id}/confirm", params: { settings: }.to_json, headers: auth_headers(user)

      expect(import.reload.settings.dig("credit_cards", "NuBank - Cartão")).to eq({ "due_day" => 10 })
    end

    it "accepts a confirmation with no settings at all" do
      post "/api/v1/imports/#{import.id}/confirm", params: {}.to_json, headers: auth_headers(user)

      expect(response).to have_http_status(:accepted)
      expect(import.reload.status).to eq("importing")
    end

    it "refuses an import that is not waiting for input" do
      other = create(:import, user:, status: "completed")

      post "/api/v1/imports/#{other.id}/confirm", params: {}.to_json, headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other.reload.status).to eq("completed")
    end
  end

  describe "GET /api/v1/imports/:id" do
    it "reports the status the client polls for" do
      import = create(:import, user:, status: "completed", report: { "imported" => 12 })

      get "/api/v1/imports/#{import.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("completed")
      expect(json.dig("data", "report", "imported")).to eq(12)
    end

    it "does not expose another user's import" do
      other = create(:import, user: create(:user))

      get "/api/v1/imports/#{other.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/imports" do
    it "lists the user's imports, newest first" do
      create(:import, user:, filename: "old.xls", created_at: 2.days.ago)
      create(:import, user:, filename: "new.xls", created_at: 1.hour.ago)

      get "/api/v1/imports", headers: auth_headers(user)

      expect(json["data"].pluck("filename")).to eq(["new.xls", "old.xls"])
    end
  end
end
