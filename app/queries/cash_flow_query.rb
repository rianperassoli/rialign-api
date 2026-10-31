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
# Only settled money, unless `unpaid` adds what is still scheduled — the card
# invoices still to be paid among it, as money leaving on their due date
# (Organizze keeps an unpaid invoice as a bill on the paying account; see
# OpenInvoicesQuery). The balance is the accounts' balance at the end of the
# bucket, transfers included.
#
# Checked to the cent against Organizze for October 2026: 02/10 is 14.796,91
# in and 16.427,06 out (31.927,06 of account expenses less a 15.500,00
# transfer), leaving 297.987,64 across all eleven accounts.
class CashFlowQuery
  # `period` is a date range: its first and last day.
  def initialize(user, period:, group: "day", unpaid: false, account: nil)
    @user = user
    @from = period.begin
    @to = period.end
    @buckets = ReportBuckets.new(period, group)
    @unpaid = unpaid
    @account = account
  end

  def call
    rows = @buckets.ranges.map { |start, finish| row(start, finish) }
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
    @daily_sums ||= begin
      sums = flows.where(date: @from..@to).group(:date, :kind).sum(:amount)
      open_invoices.each do |line|
        key = [line[:due_date], "expense"]
        sums[key] = sums.fetch(key, 0) + line[:amount]
      end
      sums
    end
  end

  # Net change per day, in money: income minus expense.
  def daily_changes
    @daily_changes ||= begin
      changes = legs.where(date: @from..@to).group(:date).sum(signed)
      open_invoices.each { |line| changes[line[:due_date]] = changes.fetch(line[:due_date], 0) - line[:amount] }
      changes
    end
  end

  def open_invoices
    return [] unless @unpaid

    @open_invoices ||= OpenInvoicesQuery.new(@user, period: @from..@to, account_id: @account&.id).call
  end

  def opening_balance
    @opening_balance ||= accounts.sum(BigDecimal(0), &:initial_balance) +
                         legs.where(date: ...@from).sum(signed)
  end

  def signed
    Arel.sql("CASE WHEN transactions.kind = 'income' THEN transactions.amount ELSE -transactions.amount END")
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
