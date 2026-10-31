require "rails_helper"

RSpec.describe Categories::SeedDefaults, type: :service do
  let(:user) { create(:user) }

  it "creates Organizze's starter categories, each with its icon and colour" do
    expected = CategoryPresets::LIST.values.sum(&:size)
    result = nil
    expect { result = described_class.call(user:) }.to change(user.categories, :count).by(expected)
    expect(result).to be_success
    expect(user.categories.find_by(name: "Mercado", kind: "expense")).to have_attributes(icon: "shopping-cart",
                                                                                         color: "#ff7043")
    expect(user.categories.find_by(name: "Salário", kind: "income")).to have_attributes(icon: "star")
  end

  it "is idempotent" do
    described_class.call(user:)
    expect { described_class.call(user:) }.not_to change(user.categories, :count)
  end
end
