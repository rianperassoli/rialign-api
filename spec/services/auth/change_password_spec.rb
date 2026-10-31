require "rails_helper"

RSpec.describe Auth::ChangePassword, type: :service do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  def call(current: "password123", password: "newpassword1", confirmation: "newpassword1")
    described_class.call(user:, current_password: current, password:, password_confirmation: confirmation)
  end

  it "changes the password" do
    expect(call).to be_success
    expect(user.reload.authenticate("newpassword1")).to be_truthy
    expect(user.authenticate("password123")).to be_falsey
  end

  it "refuses a wrong current password" do
    result = call(current: "nope")

    expect(result).to be_failure
    expect(result.errors).to include("Current password is incorrect")
    expect(user.reload.authenticate("password123")).to be_truthy
  end

  it "refuses a blank new password" do
    expect(call(password: "", confirmation: "")).to be_failure
    expect(user.reload.authenticate("password123")).to be_truthy
  end

  it "refuses a short new password" do
    expect(call(password: "short", confirmation: "short")).to be_failure
    expect(user.reload.authenticate("password123")).to be_truthy
  end

  it "refuses when the confirmation does not match" do
    expect(call(confirmation: "different1")).to be_failure
    expect(user.reload.authenticate("password123")).to be_truthy
  end
end
