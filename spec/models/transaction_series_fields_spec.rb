require "rails_helper"

RSpec.describe Transaction do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:) }
  let(:category) { create(:category, user:) }

  def build_leg(attrs = {})
    build(:transaction, user:, account:, category:, **attrs)
  end

  it "accepts a consistent installment leg" do
    leg = build_leg(series_id: SecureRandom.uuid, installment_number: 3, installment_total: 12)
    expect(leg).to be_valid
    expect(leg).to be_installment
    expect(leg).not_to be_fixed
  end

  it "treats a series leg without installment fields as fixed" do
    leg = build_leg(series_id: SecureRandom.uuid)
    expect(leg).to be_valid
    expect(leg).to be_fixed
  end

  it "rejects installment fields without a series id" do
    leg = build_leg(installment_number: 1, installment_total: 3)
    expect(leg).not_to be_valid
    expect(leg.errors[:base]).to include("installment legs need a number, a total and a series id")
  end

  it "rejects a number above the total" do
    leg = build_leg(series_id: SecureRandom.uuid, installment_number: 13, installment_total: 12)
    expect(leg).not_to be_valid
    expect(leg.errors[:installment_number]).to be_present
  end
end
