require "rails_helper"

RSpec.describe Category, type: :model do
  subject(:category) { build(:category) }

  it "takes an icon name from the app's set, or none" do
    expect(build(:category, icon: "shopping-cart")).to be_valid
    expect(build(:category, icon: nil)).to be_valid
    expect(build(:category, icon: "<svg>")).not_to be_valid
  end

  it "shows its parent's icon when it has none of its own" do
    parent = create(:category, icon: "house")
    child = create(:category, user: parent.user, parent:, icon: nil)

    expect(child.display_icon).to eq("house")
    expect(parent.display_icon).to eq("house")
  end

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
