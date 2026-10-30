require "rails_helper"

RSpec.describe ReportBuckets do
  let(:october) { Date.new(2026, 10, 1)..Date.new(2026, 10, 31) }

  it "cuts weeks from Sunday, clipped to the period" do
    buckets = described_class.new(october, "week")

    expect(buckets.ranges.first).to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 3)])
    expect(buckets.ranges.last).to eq([Date.new(2026, 10, 25), Date.new(2026, 10, 31)])
    expect(buckets.index_of(Date.new(2026, 10, 4))).to eq(1)
  end

  it "keeps the whole period as one bucket, and leaves days outside it out" do
    buckets = described_class.new(october, "total")

    expect(buckets.ranges).to eq([[october.begin, october.end]])
    expect(buckets.index_of(Date.new(2026, 11, 1))).to be_nil
  end

  it "falls back to days" do
    expect(described_class.new(october, "hourly")).to have_attributes(group: "day", size: 31)
  end
end
