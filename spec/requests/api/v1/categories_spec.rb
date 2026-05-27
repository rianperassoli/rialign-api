require "rails_helper"

RSpec.describe "Api::V1::Categories", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/categories" do
    before do
      create(:category, user:, kind: "expense", name: "Food")
      create(:income_category, user:, name: "Salary")
    end

    it "lists all categories" do
      get "/api/v1/categories", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
    end

    it "filters by kind" do
      get "/api/v1/categories", params: { kind: "income" }, headers: auth_headers(user)
      expect(json["data"].pluck("kind")).to all(eq("income"))
    end
  end

  describe "POST /api/v1/categories" do
    it "creates a category" do
      params = { category: { name: "Travel", kind: "expense", color: "#fff" } }
      expect { post "/api/v1/categories", params: params.to_json, headers: auth_headers(user) }
        .to change(user.categories, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "returns 422 on an invalid kind" do
      post "/api/v1/categories", params: { category: { name: "X", kind: "bogus" } }.to_json,
                                 headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET/PATCH/DELETE /api/v1/categories/:id" do
    let(:category) { create(:category, user:) }

    it "shows a category" do
      get "/api/v1/categories/#{category.id}", headers: auth_headers(user)
      expect(json.dig("data", "id")).to eq(category.id)
    end

    it "updates a category" do
      patch "/api/v1/categories/#{category.id}", params: { category: { name: "Renamed" } }.to_json,
                                                 headers: auth_headers(user)
      expect(category.reload.name).to eq("Renamed")
    end

    it "soft deletes a category" do
      delete "/api/v1/categories/#{category.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(category.reload).to be_archived
    end
  end
end
