require "rails_helper"

RSpec.describe Transactions::UpdateSeries, type: :service do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:other_account) { create(:account, user:) }
  let(:rent) { create(:category, user:, name: "Rent") }
  let(:housing) { create(:category, user:, name: "Housing") }
  # Fixed monthly entry, Jan..Apr; only the first occurrence starts paid.
  let!(:series) do
    Transactions::CreateSeries.call(user:, months: 4,
                                    params: { description: "Aluguel", kind: "expense", amount: 1000,
                                              date: "2026-01-10", account_id: account.id,
                                              category_id: rent.id, paid: true }).data
  end

  def edit(index, scope, **params)
    described_class.call(user:, transaction: series[index], params:, scope:)
  end

  it "spreads the change to this and the later occurrences only" do
    edit(1, "future", description: "Aluguel novo", amount: 1200)

    expect(series.map { |t| t.reload.description }).to eq(["Aluguel", "Aluguel novo", "Aluguel novo", "Aluguel novo"])
    expect(series.map { |t| t.reload.amount }).to eq([1000, 1200, 1200, 1200])
  end

  it "spreads the change to every occurrence, keeping a paid one's amount and source" do
    edit(2, "series", category_id: housing.id, amount: 1100, account_id: other_account.id)

    first = series.first.reload
    expect(first).to have_attributes(category_id: housing.id, amount: 1000, account_id: account.id)
    expect(series.drop(1).map(&:reload)).to all(have_attributes(category_id: housing.id, amount: 1100,
                                                                account_id: other_account.id))
  end

  it "keeps each occurrence's own date and paid flag" do
    edit(1, "future", date: "2026-02-15", paid: true)

    expect(series.map { |t| t.reload.date.day }).to eq([10, 15, 10, 10])
    expect(series.map { |t| t.reload.paid }).to eq([true, true, false, false])
  end

  it "counts the later ones from where the occurrence was, even when its date moves" do
    edit(2, "future", date: "2026-02-01", description: "Novo")
    expect(series.map { |t| t.reload.description }).to eq(%w[Aluguel Aluguel Novo Novo])
  end

  it "changes nothing when one occurrence cannot take the change" do
    expect(edit(1, "series", category_id: create(:income_category, user:).id)).to be_failure
    expect(series.map { |t| t.reload.category_id }.uniq).to eq([rent.id])
  end
end
