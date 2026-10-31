require "rails_helper"

RSpec.describe CategoryPresets do
  it "finds a starter category by name and kind, ignoring case and accents" do
    expect(described_class.for("saude", "expense")).to eq(icon: "cross", color: "#64b5f6")
    expect(described_class.for(" INVESTIMENTOS ", "income")).to eq(icon: "trending-up", color: "#34d399")
    expect(described_class.for("Investimentos", "expense")).to include(icon: "chart-column")
  end

  it "gives nothing for a name of its own or an unknown kind" do
    expect(described_class.for("Ranger", "expense")).to eq({})
    expect(described_class.for("Casa", "transfer")).to eq({})
  end
end
