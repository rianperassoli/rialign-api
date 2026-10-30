require "rails_helper"

RSpec.describe CashFlowQuery do
  let(:user) { create(:user) }
  let(:checking) { create(:account, user:, name: "Checking", initial_balance: 1000) }
  let(:savings) { create(:account, user:, name: "Savings", initial_balance: 500, exclude_from_total: true) }
  let(:category) { create(:category, user:) }
  let(:october) { Date.new(2026, 10, 1) }

  def query(**options)
    described_class.new(user, period: october..october.end_of_month, **options).call
  end

  def money(row)
    row.slice(:income, :expense, :net, :balance).transform_values(&:to_f)
  end

  def entry(amount, day, kind: "expense", account: checking, paid: true)
    create(:transaction, user:, account:, category: create(:category, user:, kind:), kind:, amount:, paid:,
                         date: october + (day - 1))
  end

  before do
    savings
    entry(50, 1, kind: "income")
    entry(30, 2)
    entry(999, 30, kind: "expense", paid: false)
    Transfers::CreateTransfer.call(user:, params: { from_account_id: checking.id, to_account_id: savings.id,
                                                    amount: 200, date: october + 1 })
  end

  it "lists each day with what came in and out, and every account's balance at its end" do
    rows = query[:rows]

    expect(rows.size).to eq(31)
    expect(money(rows[0])).to eq(income: 50, expense: 0, net: 50, balance: 1550)
    # The transfer moves nothing in or out overall, even to an account kept
    # out of the total balance.
    expect(money(rows[1])).to eq(income: 0, expense: 30, net: -30, balance: 1520)
    expect(money(rows.last)).to include(balance: 1520)
  end

  it "counts the account side of an invoice payment as money leaving" do
    card = create(:credit_card, user:, payment_account: checking, closing_day: 31, due_day: 10)
    create(:transaction, user:, account: nil, credit_card: card, category:, amount: 80, date: october - 20,
                         paid: false)
    CreditCards::PayInvoice.call(user:, credit_card: card, params: { month: "2026-10", date: (october + 4).to_s })

    expect(money(query[:rows][4])).to include(expense: 80, balance: 1440)
  end

  it "adds what is still to be paid when asked" do
    rows = query(unpaid: true)[:rows]

    expect(money(rows[29])).to eq(income: 0, expense: 999, net: -999, balance: 521)
    expect(money(query[:rows][29])).to include(expense: 0, balance: 1520)
  end

  it "groups by week (from Sunday) and by month, clipped to the period" do
    weeks = query(group: "week")[:rows]
    expect(weeks.first).to include(from: october, to: Date.new(2026, 10, 3))
    expect(weeks.second).to include(from: Date.new(2026, 10, 4), to: Date.new(2026, 10, 10))

    months = described_class.new(user, period: (october - 15)..october.end_of_month, group: "month").call[:rows]
    expect(months.pluck(:from)).to eq([october - 15, october])
  end

  it "sums the whole period in one row, with the totals alongside" do
    result = query(group: "total")

    expect(result[:rows].sole).to include(from: october, to: october.end_of_month)
    expect(result[:totals].transform_values(&:to_f)).to eq(income: 50, expense: 30, net: 20)
  end

  it "shows one account with its transfers as money in and out" do
    rows = query(account: savings)[:rows]

    expect(money(rows[1])).to eq(income: 200, expense: 0, net: 200, balance: 700)
  end

  it "falls back to days on an unknown grouping" do
    expect(query(group: "hourly")[:rows].size).to eq(31)
  end
end
