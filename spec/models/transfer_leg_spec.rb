require "rails_helper"

RSpec.describe TransferLeg do
  let(:user) { create(:user) }
  let(:leg) do
    user.transactions.create!(account: create(:account, user:), kind: "expense", amount: 40,
                              date: Date.current, description: "Pix", transfer_id: SecureRandom.uuid)
  end

  it "takes a new description or notes on its own" do
    expect(leg.update(description: "Reserva", notes: "obs")).to be(true)
  end

  it "refuses to change what it moves on its own" do
    expect(leg.update(amount: 50)).to be(false)
    expect(leg.errors[:base]).to include("a transfer leg can only be changed together with the transfer")
  end

  it "changes what it moves when edited as part of the pair" do
    leg.editing_as_pair = true
    expect(leg.update(amount: 50)).to be(true)
  end

  it "leaves regular transactions alone" do
    expect(create(:transaction, user:).update(amount: 50)).to be(true)
  end
end
