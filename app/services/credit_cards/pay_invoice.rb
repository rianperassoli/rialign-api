module CreditCards
  # Pays a card's open invoice from a bank account.
  #
  # The card's pending expenses are realized (marked paid, so they finally count
  # as real spending in reports) and the cash leaving the bank account is
  # recorded as a settlement leg on the payment account. That leg carries a
  # `transfer_id` so it lowers the account balance WITHOUT being double-counted
  # as a second expense in income/expense reports (the card transactions already
  # represent the spending).
  #
  # The account defaults to the card's `payment_account`, but an explicit
  # `account_id` can override it (e.g. paying from a different account once).
  #
  # With a `month` (YYYY-MM) param only the charges up to that invoice's
  # closing date are settled — later cycles stay open. Without it, every
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

      pending = @card.transactions.expense.pending
      pending = pending.where(date: ..invoice_closing_date) if invoice_closing_date
      total = pending.sum(:amount)
      return failure("No open invoice to pay") if total.zero?

      settlement = nil
      ApplicationRecord.transaction do
        # Bulk update on purpose: flipping `paid` has no validations or callbacks
        # to run, and an invoice can cover hundreds of rows. updated_at is set
        # explicitly since update_all skips timestamping.
        pending.update_all(paid: true, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        settlement = build_settlement(account:, total:)
        settlement.save!
      end
      success(transaction: settlement, amount: total, account: account)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors)
    end

    private

    # Closing date of the requested invoice month, or nil to pay everything.
    def invoice_closing_date
      return @invoice_closing_date if defined?(@invoice_closing_date)

      @invoice_closing_date =
        if @params[:month].present?
          month = Date.strptime(@params[:month].to_s, "%Y-%m")
          CreditCardInvoiceQuery.new(@card, month: month).period[:to]
        end
    rescue ArgumentError
      @invoice_closing_date = nil
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
