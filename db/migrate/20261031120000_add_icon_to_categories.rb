# A category's picture (a name from the web app's icon set). Existing
# categories named like one of the starter set (see CategoryPresets) get its
# icon, so an Organizze import already in place gains them too.
class AddIconToCategories < ActiveRecord::Migration[8.0]
  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    add_column :categories, :icon, :string
    MigrationCategory.reset_column_information

    MigrationCategory.find_each do |category|
      icon = CategoryPresets.for(category.name, category.kind)[:icon]
      category.update_column(:icon, icon) if icon # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    remove_column :categories, :icon
  end
end
