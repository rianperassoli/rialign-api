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

      settlement = nil
      ApplicationRecord.transaction do
        # Bulk update on purpose: flipping `paid` has no validations or callbacks
        # to run, and an invoice can cover hundreds of rows. updated_at is set
        # explicitly since update_all skips timestamping. The settlement is saved
        # first so each charge can point at it — that link is what lets the
        # payment be cancelled (see Transaction#archive!).
        settlement = build_settlement(account:, total:)
        settlement.save!
        pending.update_all(paid: true, settled_by_id: settlement.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
      success(transaction: settlement, amount: total, account: account)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

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

    def build_settlement(account:, total:)
      @user.transactions.new(
        account: account,
        kind: "expense",
        transfer_id: SecureRandom.uuid,
        description: "#{@card.name} invoice payment",
        amount: total,
        date: @params[:date] || Date.current,
        paid: true
      )
    end
  end
end
