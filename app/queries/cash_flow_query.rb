# Organizze's "Entradas x Saídas": the money that came into and left the
# accounts over a period, bucketed by day, week or month (or the period as a
# whole), with the balance at the end of each bucket.
#
#  - Overall: every account in reais — even the ones kept out of the
#    dashboard's total balance, which Organizze's report still adds in. A
#    transfer between accounts brings nothing in and takes nothing out, so it
#    is left out; paying a card invoice is money leaving, so it counts — the
#    purchases behind it never touched an account.
#  - One account: everything on it, its transfers included, since for that
#    account they are money in and out.
#
# Only settled money, unless `unpaid` adds what is still scheduled. The
# balance is the accounts' balance at the end of the bucket, transfers
# included.
#
# Checked to the cent against Organizze for October 2026: 02/10 is 14.796,91
# in and 16.427,06 out (31.927,06 of account expenses less a 15.500,00
# transfer), leaving 297.987,64 across all eleven accounts.
class CashFlowQuery
  GROUPS = %w[day week month total].freeze

  # `period` is a date range: its first and last day.
  def initialize(user, period:, group: "day", unpaid: false, account: nil)
    @user = user
    @from = period.begin
    @to = period.end
    @group = GROUPS.include?(group) ? group : "day"
    @unpaid = unpaid
    @account = account
  end

  def call
    rows = buckets.map { |start, finish| row(start, finish) }
    {
      period: { from: @from, to: @to },
      rows: rows,
      totals: totals(rows)
    }
  end

  private

  def accounts
    @accounts ||= @account ? [@account] : @user.accounts.in_base_currency.to_a
  end

  # Every leg on the accounts: what their balance is made of.
  def legs
    scope = Transaction.where(account_id: accounts.map(&:id))
    @unpaid ? scope : scope.paid
  end

  # What counts as in and out: overall, transfers between accounts drop out
  # but the account side of an invoice payment stays (every leg of it, as an
  # imported payment can come in two goes).
  def flows
    return legs if @account

    payments = Transaction.where(id: @user.transactions.where.not(settled_by_id: nil).select(:settled_by_id))
    legs.where(transfer_id: nil).or(legs.where(transfer_id: payments.select(:transfer_id)))
  end

  def daily_sums
    @daily_sums ||= flows.where(date: @from..@to).group(:date, :kind).sum(:amount)
  end

  # Net change per day, in money: income minus expense.
  def daily_changes
    @daily_changes ||= legs.where(date: @from..@to).group(:date).sum(signed)
  end

  def opening_balance
    @opening_balance ||= accounts.sum(BigDecimal(0), &:initial_balance) +
                         legs.where(date: ...@from).sum(signed)
  end

  def signed
    Arel.sql("CASE WHEN transactions.kind = 'income' THEN transactions.amount ELSE -transactions.amount END")
  end

  # [first day, last day] of each bucket, clipped to the period.
  def buckets
    return [[@from, @to]] if @group == "total"

    starts = (@from..@to).map { |day| bucket_start(day) }.uniq
    starts.each_with_index.map do |start, index|
      finish = starts[index + 1] ? starts[index + 1] - 1 : @to
      [start, finish]
    end
  end

  def bucket_start(day)
    start = case @group
            when "week" then day.beginning_of_week(:sunday)
            when "month" then day.beginning_of_month
            else day
            end
    [start, @from].max
  end

  def row(start, finish)
    days = start..finish
    income = sum_for(days, "income")
    expense = sum_for(days, "expense")
    { from: start, to: finish, income:, expense:, net: income - expense, balance: balance_at(finish) }
  end

  def sum_for(days, kind)
    daily_sums.sum(BigDecimal(0)) { |(day, row_kind), total| days.cover?(day) && row_kind == kind ? total : 0 }
  end

  def balance_at(day)
    opening_balance + daily_changes.sum(BigDecimal(0)) { |date, change| date <= day ? change : 0 }
  end

  def totals(rows)
    income = rows.sum(BigDecimal(0)) { |row| row[:income] }
    expense = rows.sum(BigDecimal(0)) { |row| row[:expense] }
    { income:, expense:, net: income - expense }
  end
end
