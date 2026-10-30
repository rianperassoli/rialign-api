require "rails_helper"

RSpec.describe Imports::InstallmentSeries do
  describe ".parse" do
    it "reads the parcel at the end of a description" do
      expect(described_class.parse(" Tv pai 8/12 ")).to eq(description: "Tv pai", installment_number: 8,
                                                           installment_total: 12)
    end

    it "ignores what cannot be a parcel" do
      expect(described_class.parse("Mercado")).to be_nil
      expect(described_class.parse("Rendimento 08/2026")).to be_nil
      expect(described_class.parse("Algo 0/3")).to be_nil
      expect(described_class.parse("Algo 4/3")).to be_nil
      expect(described_class.parse("Algo 1/1")).to be_nil
      expect(described_class.parse("1/2")).to be_nil
    end
  end

  describe ".assign" do
    def parcel(key, date, number, description: "TV", total: 3)
      [key, Date.parse(date), { description:, installment_number: number, installment_total: total }]
    end

    it "chains each parcel to the one before it, in date order" do
      ids = described_class.assign([parcel(:c, "2026-03-01", 3), parcel(:a, "2026-01-01", 1),
                                    parcel(:b, "2026-02-01", 2), parcel(:x, "2026-01-05", 1, description: "Sofá")])

      expect(ids.values_at(:a, :b, :c).uniq.size).to eq(1)
      expect(ids[:x]).not_to eq(ids[:a])
    end

    it "keeps the same thing bought twice as two series" do
      ids = described_class.assign([parcel(:a1, "2026-01-01", 1), parcel(:b1, "2026-01-01", 1),
                                    parcel(:a2, "2026-02-01", 2), parcel(:b2, "2026-02-01", 2)])

      expect(ids[:a1]).to eq(ids[:a2])
      expect(ids[:b1]).to eq(ids[:b2])
      expect(ids[:a1]).not_to eq(ids[:b1])
    end
  end
end
