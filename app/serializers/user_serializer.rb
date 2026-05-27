class UserSerializer < ApplicationSerializer
  private

  def attributes
    {
      id: object.id,
      name: object.name,
      email: object.email,
      created_at: object.created_at
    }
  end
end
