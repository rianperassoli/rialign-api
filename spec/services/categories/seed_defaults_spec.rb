require "rails_helper"

RSpec.describe Categories::SeedDefaults, type: :service do
  let(:user) { create(:user) }

  it "creates the default income and expense categories" do
    expected = described_class::DEFAULTS.values.sum(&:size)
    result = nil
    expect { result = described_class.call(user:) }.to change(user.categories, :count).by(expected)
    expect(result).to be_success
    expect(user.categories.where(kind: "income")).to exist
    expect(user.categories.where(kind: "expense")).to exist
  end

  it "is idempotent" do
    described_class.call(user:)
    expect { described_class.call(user:) }.not_to change(user.categories, :count)
  end
end
