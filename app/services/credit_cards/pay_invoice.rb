module CreditCards
  # Pays a card's open invoice from a bank account.
  #
  # The card's pending charges and credits are realized (marked paid, so they finally count
  # as real spending in reports) and the cash leaving the bank account is
  # recorded as a settlement leg on the payment account. That leg carries a
  # `transfer_id` so it lowers the account balance WITHOUT being double-counted
  # as a second expense in income/expense reports (the card transactions already
  # represent the spending). Every charge it settles points back at it, so
  # deleting the payment reopens them.
  #
  # The account defaults to the card's `payment_account`, but an explicit
  # `account_id` can override it (e.g. paying from a different account once).
  #
  # With a `month` (YYYY-MM) param only the charges on that invoice and earlier
  # ones still unpaid are settled — later invoices stay open. Without it, every
  # pending charge on the card is settled.
  #
  # An `amount` below the total is a partial payment, as Organizze does it: the
  # invoice is still settled, and what was left unpaid moves to the next invoice
  # as one "remaining balance" charge. That charge is a second leg of the same
  # payment (same `transfer_id`): it uses the card limit, stays out of reports
  # (the purchases behind it were already counted) and goes away with the
  # payment when it is undone. It needs a `month`, the invoice it rolls out of.
  class PayInvoice < ApplicationService
    def initialize(user:, credit_card:, params: {})
      @user = user
      @card = credit_card
      @params = params.to_h.symbolize_keys
    end

    def call
      account = resolve_account
      return failure("No payment account set for this card") if account.nil?

      # Pending credits are settled with the charges they offset. When credits
      # outweigh the charges there is nothing to pay: they stay pending and
      # carry over to the next invoice.
      pending = @card.transactions.pending
      pending = pending.where(invoice_month: ..invoice_month) if invoice_month
      total = pending.charged_total
      return failure("No open invoice to pay") unless total.positive?

      paying = amount_paid(total)
      error = amount_error(paying, total)
      return failure(error) if error

      settlement = settle(pending, account:, paying:, remaining: total - paying)
      success(transaction: settlement, amount: paying, account: account, remaining: total - paying)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    # Bulk update on purpose: flipping `paid` has no validations or callbacks
    # to run, and an invoice can cover hundreds of rows. updated_at is set
    # explicitly since update_all skips timestamping. The settlement is saved
    # first so each charge can point at it — that link is what lets the
    # payment be cancelled (see InvoiceSettlement).
    def settle(pending, account:, paying:, remaining:)
      transfer_id = SecureRandom.uuid
      ApplicationRecord.transaction do
        settlement = build_settlement(account:, amount: paying, transfer_id:)
        settlement.save!
        pending.update_all(paid: true, settled_by_id: settlement.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        build_remaining_balance(remaining, transfer_id:).save! if remaining.positive?
        settlement
      end
    end

    # The whole invoice unless an amount is given.
    def amount_paid(total)
      return total if @params[:amount].blank?

      BigDecimal(@params[:amount].to_s)
    rescue ArgumentError
      BigDecimal(0)
    end

    def amount_error(paying, total)
      return "Amount must be greater than zero" unless paying.positive?
      return "Amount cannot exceed the invoice total" if paying > total

      "A partial payment needs the invoice month" if paying < total && invoice_month.nil?
    end

    # The requested invoice month, or nil to pay everything.
    def invoice_month
      return @invoice_month if defined?(@invoice_month)

      @invoice_month = (Date.strptime(@params[:month].to_s, "%Y-%m") if @params[:month].present?)
    rescue ArgumentError
      @invoice_month = nil
    end

    def resolve_account
      if @params[:account_id].present?
        @user.accounts.find_by(id: @params[:account_id])
      else
        @card.payment_account
      end
    end

    def payment_date
      @params[:date] || Date.current
    end

    def build_settlement(account:, amount:, transfer_id:)
      @user.transactions.new(
        account: account,
        kind: "expense",
        transfer_id: transfer_id,
        description: "#{@card.name} invoice payment",
        amount: amount,
        date: payment_date,
        paid: true
      )
    end

    def build_remaining_balance(amount, transfer_id:)
      @user.transactions.new(
        credit_card: @card,
        kind: "expense",
        transfer_id: transfer_id,
        description: "Remaining balance of the #{invoice_month.strftime("%Y-%m")} invoice",
        amount: amount,
        date: payment_date,
        invoice_month: invoice_month >> 1,
        paid: false
      )
    end
  end
end
