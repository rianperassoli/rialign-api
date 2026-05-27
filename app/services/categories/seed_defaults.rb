module Categories
  # Idempotently creates a sensible starter set of categories for a user.
  class SeedDefaults < ApplicationService
    DEFAULTS = {
      "income" => [
        ["Salary", "#2ecc71"],
        ["Investments", "#27ae60"],
        ["Other income", "#16a085"]
      ],
      "expense" => [
        ["Housing", "#e74c3c"],
        ["Food", "#e67e22"],
        ["Transport", "#f39c12"],
        ["Health", "#9b59b6"],
        ["Leisure", "#3498db"],
        ["Other expenses", "#95a5a6"]
      ]
    }.freeze

    def initialize(user:)
      @user = user
    end

    def call
      DEFAULTS.each do |kind, entries|
        entries.each do |name, color|
          @user.categories.find_or_create_by!(name:, kind:) do |category|
            category.color = color
          end
        end
      end
      success(@user.categories)
    end
  end
end
