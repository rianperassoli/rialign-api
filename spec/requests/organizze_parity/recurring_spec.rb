require "rails_helper"

# Entries that repeat — a fixed entry for some months, one with no end date,
# installments on an account — created, edited and deleted through the API the
# way Organizze offers it: "somente esta", "esta e as próximas", "todas".
RSpec.describe "Organizze parity: recurring entries", type: :request do
  include OrganizzeScenario

  let(:user) { create(:user) }
  let(:nubank) { account("NuBank", initial_balance: 5000) }
  let(:gym) { category("Academia") }

  before { travel_to Date.new(2026, 10, 15) }

  def occurrences(search)
    transactions(search:).sort_by { |t| t["date"] }
  end

  def edit(occurrence, scope, **changes)
    api(:patch, "/transactions/#{occurrence["id"]}?scope=#{scope}", { transaction: changes }, expect: :ok)
  end

  def delete_occurrence(occurrence, scope)
    api(:delete, "/transactions/#{occurrence["id"]}?scope=#{scope}", expect: :no_content)
  end

  describe "a fixed entry for 12 months" do
    before { entry("Academia", 100, on: nubank, category: gym, date: "2026-10-05", fixed_months: 12) }

    it "repeats every month on the same day, only the first already paid" do
      all = occurrences("Academia")

      expect(all.size).to eq(12)
      expect(all.pluck("date").first(3)).to eq(%w[2026-10-05 2026-11-05 2026-12-05])
      expect(all.pluck("paid").tally).to eq(true => 1, false => 11)
      expect(balance_of(nubank)).to eq(4900)
      expect(money(dashboard("2026-11")["forecast"]["expense"])).to eq(100)
    end

    it "changes this and the following occurrences, keeping a paid one as it was" do
      edit(occurrences("Academia")[2], "future", amount: 120)

      expect(occurrences("Academia").map { |t| money(t["amount"]) }.first(4)).to eq([100, 100, 120, 120])
    end

    it "renames every occurrence, each keeping its own date" do
      edit(occurrences("Academia")[5], "series", description: "Smart Fit", date: "2027-03-20")

      renamed = occurrences("Smart Fit")
      expect(renamed.size).to eq(12)
      expect(renamed.pluck("date")).to include("2027-03-20", "2027-02-05", "2027-04-05")
    end

    it "changes only the chosen occurrence" do
      edit(occurrences("Academia")[1], "one", amount: 150)
      expect(occurrences("Academia").map { |t| money(t["amount"]) }.count(150)).to eq(1)
    end

    it "deletes one occurrence, or this one and the following" do
      delete_occurrence(occurrences("Academia")[3], "one") # January 2027
      expect(occurrences("Academia").pluck("date")).not_to include("2027-01-05")

      delete_occurrence(occurrences("Academia")[5], "future") # April 2027 onwards
      expect(occurrences("Academia").pluck("date").last(2)).to eq(%w[2027-02-05 2027-03-05])
    end
  end

  describe "a fixed entry with no end date" do
    before { entry("Netflix", 40, on: nubank, category: gym, date: "2026-10-10", fixed: true) }

    it "always has the next 12 months created and keeps going as time passes" do
      expect(occurrences("Netflix").pluck("date").last).to eq("2027-10-10")

      travel_to Date.new(2026, 12, 20)
      expect(occurrences("Netflix").pluck("date").last).to eq("2027-12-10")
    end

    it "stops for good when this and the following occurrences are deleted" do
      delete_occurrence(occurrences("Netflix")[2], "future")

      travel_to Date.new(2027, 3, 1)
      expect(occurrences("Netflix").pluck("date")).to eq(%w[2026-10-10 2026-11-10])
    end

    it "carries a change to this and the following occurrences into the months created later" do
      edit(occurrences("Netflix").last, "future", amount: 45)

      travel_to Date.new(2027, 1, 20)
      expect(money(occurrences("Netflix").last["amount"])).to eq(45)
    end
  end

  describe "installments on an account" do
    before { entry("Curso", 600, on: nubank, category: gym, date: "2026-10-01", installments: 3) }

    it "splits the total into monthly parcels labelled 1/3, 2/3, 3/3" do
      parcels = occurrences("Curso")

      expect(parcels.map { |t| money(t["amount"]) }).to eq([200, 200, 200])
      expect(parcels.pluck("installment_number")).to eq([1, 2, 3])
      expect(balance_of(nubank)).to eq(4800)
    end

    it "drops the parcels still to come" do
      delete_occurrence(occurrences("Curso")[1], "future")
      expect(occurrences("Curso").size).to eq(1)
    end
  end
end
