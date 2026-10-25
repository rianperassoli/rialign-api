require "rails_helper"

RSpec.describe Category do
  describe "subcategories" do
    let(:user) { create(:user) }
    let(:food) { create(:category, user:, name: "Alimentação", color: "#e67e22") }

    def sub(**attrs)
      build(:category, user:, name: "Mercado", parent: food, **attrs)
    end

    it "sits under a top-level category of the same user and kind" do
      expect(sub).to be_valid
    end

    it "rejects a parent of another user, another kind, or itself a subcategory" do
      expect(build(:category, user:, parent: create(:category)).tap(&:valid?).errors[:parent])
        .to include("must belong to the same user")
      expect(sub(kind: "income").tap(&:valid?).errors[:parent]).to include("must be of the same kind")

      market = sub.tap(&:save!)
      expect(build(:category, user:, parent: market).tap(&:valid?).errors[:parent])
        .to include("must be a top-level category")
    end

    it "keeps a category with subcategories, or the category itself, from becoming a child" do
      sub.save!
      expect(food.tap { |c| c.parent = create(:category, user:) }.tap(&:valid?).errors[:parent])
        .to include("cannot have subcategories of its own")

      lone = create(:category, user:)
      expect(lone.tap { |c| c.parent = lone }.tap(&:valid?).errors[:parent]).to include("cannot be the category itself")
    end

    it "refuses an archived parent for a new subcategory" do
      food.archive!
      expect(sub.tap(&:valid?).errors[:parent]).to include("is archived")
    end

    it "archives its subcategories with it" do
      market = sub.tap(&:save!)
      food.archive!
      expect(described_class.unscoped.find(market.id)).to be_archived
      expect { food.archive! }.not_to raise_error
    end

    it "shows the parent's color when it has none" do
      expect(sub(color: nil).display_color).to eq("#e67e22")
      expect(sub(color: "#000000").display_color).to eq("#000000")
      expect(build(:category, color: nil).display_color).to be_nil
    end
  end
end
