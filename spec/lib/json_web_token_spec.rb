require "rails_helper"

RSpec.describe JsonWebToken do
  it "round-trips a payload" do
    token = described_class.encode({ user_id: 7 })
    expect(described_class.decode(token)[:user_id]).to eq(7)
  end

  it "stamps an expiry claim" do
    token = described_class.encode({ user_id: 1 })
    expect(described_class.decode(token)).to have_key("exp")
  end

  it "returns nil for an expired token" do
    token = described_class.encode({ user_id: 1 }, exp: 1.hour.ago)
    expect(described_class.decode(token)).to be_nil
  end

  it "returns nil for a malformed token" do
    expect(described_class.decode("not.a.token")).to be_nil
  end

  it "uses JWT_SECRET_KEY when set" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("JWT_SECRET_KEY").and_return("custom-secret")
    expect(described_class.secret_key).to eq("custom-secret")
  end

  it "falls back to the app secret_key_base" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("JWT_SECRET_KEY").and_yield
    expect(described_class.secret_key).to eq(Rails.application.secret_key_base)
  end
end
