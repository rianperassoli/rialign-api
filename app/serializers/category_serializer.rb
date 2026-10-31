class CategorySerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      name: object.name,
      kind: object.kind,
      color: object.display_color,
      icon: object.display_icon,
      parent_id: object.parent_id,
      archived: object.archived?
    }
  end
end
