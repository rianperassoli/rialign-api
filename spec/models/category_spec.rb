require "rails_helper"

RSpec.describe Category, type: :model do
  subject(:category) { build(:category) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:transactions).dependent(:restrict_with_error) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:kind) }
  it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }

  it "soft deletes even when it has transactions" do
    transaction = create(:transaction)
    category = transaction.category
    expect { category.destroy }.not_to raise_error
    expect(category.reload).to be_archived
  end

  describe "changing kind" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user:, kind: "expense") }

    it "is free while nothing uses the category" do
      expect(category.update(kind: "income")).to be(true)
    end

    it "is refused once an entry, even an archived one, sits on it" do
      create(:transaction, user:, category:).archive!
      expect(category.update(kind: "income")).to be(false)
      expect(category.errors[:kind]).to be_present
    end

    it "is refused once it has a subcategory" do
      create(:category, user:, kind: "expense", parent: category)
      expect(category.update(kind: "income")).to be(false)
    end

    it "does not stop other changes to a category in use" do
      create(:transaction, user:, category:)
      expect(category.update(name: "Outro")).to be(true)
    end
  end
end
