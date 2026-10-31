require "rails_helper"

RSpec.describe Auth::DeleteAccount, type: :service do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  # A user with a bit of everything, including archived rows (which a plain
  # `destroy` would leave behind).
  def populate(owner)
    account = create(:account, user: owner)
    card = create(:credit_card, user: owner)
    parent = create(:category, user: owner, name: "Parent")
    create(:category, user: owner, name: "Child", parent:)
    create(:transaction, user: owner, account:, category: parent)
    create(:import, user: owner)
    account.archive!
    card
  end

  it "deletes the user and all their data for real, archived rows included" do
    populate(user)

    result = nil
    expect { result = described_class.call(user:, password: "password123") }.to change(User, :count).by(-1)

    expect(result).to be_success
    [Transaction, Account, CreditCard, Category, Import, Recurrence].each do |model|
      expect(model.unscoped.where(user_id: user.id)).to be_empty, "#{model} rows were left behind"
    end
  end

  it "leaves other users untouched" do
    other = create(:user)
    populate(other)
    populate(user)

    described_class.call(user:, password: "password123")

    expect(User.exists?(other.id)).to be(true)
    expect(Account.unscoped.where(user_id: other.id)).to exist
    expect(Category.unscoped.where(user_id: other.id)).to exist
  end

  it "refuses a wrong password and deletes nothing" do
    populate(user)

    result = nil
    expect { result = described_class.call(user:, password: "nope") }.not_to change(User, :count)

    expect(result).to be_failure
    expect(result.errors).to include("Password is incorrect")
    expect(Account.unscoped.where(user_id: user.id)).to exist
  end
end
