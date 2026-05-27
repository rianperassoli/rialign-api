class CategorySerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      name: object.name,
      kind: object.kind,
      color: object.color,
      archived: object.archived?
    }
  end
end
