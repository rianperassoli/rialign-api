require "rails_helper"

RSpec.describe Transactions::CreateSeries do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:, kind: "expense") }

  let(:base_params) do
    {
      description: "Sofa",
      kind: "expense",
      amount: 1000,
      date: "2026-01-31",
      paid: true,
      category_id: category.id,
      account_id: account.id
    }
  end

  describe "installments" do
    subject(:result) { described_class.call(user:, params: base_params, installments: 3) }

    it "creates one leg per installment sharing a series id" do
      expect { result }.to change(user.transactions, :count).by(3)
      expect(result.data.map(&:series_id).uniq.size).to eq(1)
      expect(result.data.map(&:installment_number)).to eq([1, 2, 3])
      expect(result.data.map(&:installment_total).uniq).to eq([3])
    end

    it "splits the total with the cent remainder on the first leg" do
      legs = described_class.call(user:, params: base_params.merge(amount: 100), installments: 3).data
      expect(legs.map(&:amount)).to eq([33.34, 33.33, 33.33])
      expect(legs.sum(&:amount)).to eq(100)
    end

    it "advances monthly, clamping short months" do
      expect(result.data.map(&:date)).to eq([
                                              Date.new(2026, 1, 31),
                                              Date.new(2026, 2, 28),
                                              Date.new(2026, 3, 31)
                                            ])
    end

    it "keeps paid only on the first occurrence" do
      expect(result.data.map(&:paid)).to eq([true, false, false])
    end
  end

  describe "fixed series" do
    subject(:result) { described_class.call(user:, params: base_params, months: 3) }

    it "repeats the amount untouched without installment fields" do
      expect(result.data.map(&:amount).uniq).to eq([1000])
      expect(result.data.map(&:installment_number).uniq).to eq([nil])
      expect(result.data.map(&:series_id).uniq.size).to eq(1)
    end
  end

  describe "validation" do
    it "rejects a series of one occurrence" do
      result = described_class.call(user:, params: base_params, installments: 1)
      expect(result).to be_failure
    end

    it "rejects a series beyond the cap" do
      result = described_class.call(user:, params: base_params, months: 61)
      expect(result).to be_failure
    end

    it "rolls everything back when one leg is invalid" do
      params = base_params.merge(category_id: nil)
      expect { described_class.call(user:, params:, installments: 3) }
        .not_to change(user.transactions, :count)
    end
  end
end
