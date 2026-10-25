class AddParentToCategories < ActiveRecord::Migration[8.0]
  # One level of subcategories, as in Organizze ("Alimentação › Mercado").
  # Reports add a subcategory into its parent.
  def change
    add_reference :categories, :parent, foreign_key: { to_table: :categories }, index: true
  end
end
