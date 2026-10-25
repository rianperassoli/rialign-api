require "rails_helper"

RSpec.describe TransactionReferences do
  let(:user) { create(:user) }
  let(:category) { create(:category, user:) }
  let(:card) { create(:credit_card, user:) }

  describe "ownership" do
    it "rejects another user's category, account or card" do
      t = build(:transaction, user:, category: create(:category), account: create(:account))
      expect(t).to be_invalid
      expect(t.errors[:category]).to include("must belong to the same user")
      expect(t.errors[:account]).to include("must belong to the same user")

      charge = build(:transaction, user:, category:, account: nil, credit_card: create(:credit_card))
      expect(charge).to be_invalid
      expect(charge.errors[:credit_card]).to include("must belong to the same user")
    end
  end

  describe "archived references" do
    it "keeps an entry on an archived category editable and categorized" do
      t = create(:transaction, user:, category:)
      category.archive!

      t.reload
      expect(t.category).to eq(category)
      expect(t.update(description: "Mercado")).to be(true)
    end

    it "keeps a charge on an archived card on its invoice when edited" do
      charge = create(:transaction, user:, category:, account: nil, credit_card: card, paid: false,
                                    invoice_month: Date.new(2026, 12, 1))
      card.archive!

      charge.reload.update!(description: "Livro")
      expect(charge.reload.invoice_month).to eq(Date.new(2026, 12, 1))
    end

    it "rejects a new entry on an archived category, account or card" do
      account = create(:account, user:)
      [category, account, card].each(&:archive!)

      t = build(:transaction, user:, category:, account:)
      expect(t).to be_invalid
      expect(t.errors[:category]).to include("is archived")
      expect(t.errors[:account]).to include("is archived")

      charge = build(:transaction, user:, category: create(:category, user:), account: nil, credit_card: card)
      expect(charge).to be_invalid
      expect(charge.errors[:credit_card]).to include("is archived")
    end

    it "rejects moving an existing entry onto an archived category" do
      t = create(:transaction, user:, category:)
      archived = create(:category, user:)
      archived.archive!

      expect(t.update(category: archived)).to be(false)
      expect(t.errors[:category]).to include("is archived")
    end

    it "still counts an archived category in the month's breakdown" do
      create(:transaction, user:, category:, amount: 40)
      category.archive!

      breakdown = DashboardQuery.new(user).call[:by_category]
      expect(breakdown).to contain_exactly(include(category_id: category.id, total: 40))
    end
  end
end
