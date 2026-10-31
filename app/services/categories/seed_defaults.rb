module Categories
  # Idempotently creates Organizze's starter categories for a user, each with
  # its icon and colour (see CategoryPresets).
  class SeedDefaults < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      CategoryPresets::LIST.each do |kind, presets|
        presets.each do |name, (icon, color)|
          @user.categories.find_or_create_by!(name:, kind:) do |category|
            category.icon = icon
            category.color = color
          end
        end
      end
      success(@user.categories)
    end
  end
end
