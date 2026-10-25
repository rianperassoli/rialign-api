require "rails_helper"

RSpec.describe Recurrences::Extend, type: :service do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:) }
  let(:params) do
    { description: "Aluguel", kind: "expense", amount: 1000, date: "2026-01-31", paid: true,
      account_id: account.id, category_id: category.id }
  end

  before { travel_to Date.new(2026, 3, 15) }

  def start
    Recurrences::Start.call(user:, params:)
  end

  def series
    user.transactions.where(series_id: user.recurrences.sole.series_id).order(:date)
  end

  it "creates the first occurrence as submitted and the months up to a year ahead" do
    first = start.data

    expect(first).to have_attributes(paid: true, date: Date.new(2026, 1, 31))
    # Up to 15/03/2027: Jan 2026 .. Feb 2027 (31/03/2027 is past the horizon).
    expect(series.count).to eq(14)
    expect(series.last.date).to eq(Date.new(2027, 2, 28))
    expect(series.drop(1).map(&:paid).uniq).to eq([false])
    expect(series.map(&:date)).to include(Date.new(2026, 2, 28))
  end

  it "tops up a rule that fell behind, as time passes, and leaves an up-to-date one alone" do
    start
    travel_to Date.new(2026, 6, 1)

    expect { described_class.due(user:) }.to change(series, :count).by(3)
    expect(user.recurrences.sole.extended_through).to eq(Date.new(2027, 5, 31))
    expect { described_class.due }.not_to change(series, :count)
  end

  it "creates nothing for a rule already a year ahead" do
    start
    expect(described_class.call(user.recurrences.sole).data).to be_empty
  end

  it "never brings back a month deleted on its own" do
    start
    series.last.destroy
    travel_to Date.new(2026, 5, 1)
    described_class.due

    expect(series.pluck(:date)).not_to include(Date.new(2027, 2, 28))
    expect(series.last.date).to eq(Date.new(2027, 4, 30))
  end

  it "copies the latest occurrence, so later edits carry on" do
    start
    series.last.update!(amount: 1200, description: "Aluguel novo")
    travel_to Date.new(2026, 4, 1)
    described_class.due

    expect(series.last).to have_attributes(amount: 1200, description: "Aluguel novo", date: Date.new(2027, 3, 31))
  end

  it "ends the rule once no occurrence is left" do
    start
    series.each(&:destroy)
    travel_to Date.new(2026, 5, 1)

    described_class.due
    expect(user.recurrences.reload).to be_empty
  end

  it "ends the rule when its category was archived" do
    start
    category.archive!
    travel_to Date.new(2026, 5, 1)

    expect(described_class.call(user.recurrences.sole)).to be_failure
    expect(user.recurrences.reload).to be_empty
  end

  it "reports a first occurrence that cannot be saved, creating nothing" do
    params[:amount] = 0
    expect(start).to be_failure
    expect(Recurrence.count).to eq(0)
  end
end
