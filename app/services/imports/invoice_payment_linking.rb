module Imports
  # Links each invoice payment in an Organizze export to the invoice it paid.
  #
  # The export books a payment on the account it left ("Pagamento de fatura")
  # and names neither the card nor the invoice. Once linked the way
  # CreditCards::PayInvoice links one — every charge on the invoice points at
  # the payment — it leaves the transfers list, shows on its invoice and can be
  # cancelled like a payment made in Rialign (see InvoiceSettlement).
  #
  # Read in date order, a payment goes to an invoice due within WINDOW days of
  # it, on any card, not linked yet:
  #  - the one whose total it matches;
  #  - else the one it and the next payment match together (an invoice paid in
  #    two goes), which then share a transfer_id and are one payment;
  #  - else the one due closest: in Organizze a charge can sit on an invoice
  #    other than the one it was paid with, so the amount is off by it. Totals
  #    do not depend on the link.
  # A payment with no invoice in reach stays a one-sided transfer leg.
  #
  # Only settled invoices are linked: an open one is paid in Rialign.
  class InvoicePaymentLinking
    CATEGORY = "Pagamento de fatura".freeze
    WINDOW = 20

    def initialize
      @payments = []
    end

    # Collects a leg as the import creates it, if its row is an invoice payment.
    def add(leg, category:)
      @payments << leg if category.to_s.strip == CATEGORY && leg.account_id && !leg.income?
    end

    def call
      return { invoice_payments_linked: 0, invoice_payments_unlinked: 0 } if @payments.empty?

      @invoices = settled_invoices
      payments = @payments.sort_by { |p| [p.date, p.id] }
      linked = 0
      until payments.empty?
        payment = payments.shift
        linked += link(payment, payments)
      end
      { invoice_payments_linked: linked, invoice_payments_unlinked: @payments.size - linked }
    end

    private

    # Returns how many payments it linked.
    def link(payment, rest)
      reach = in_reach(payment)
      return 0 if reach.empty?

      exact = matching(reach, payment.amount)
      return settle(exact, payment) if exact

      split = rest.first && matching(reach, payment.amount + rest.first.amount)
      return settle(split, payment, rest.shift) if split

      settle(reach.first, payment)
    end

    # Invoices due near the payment, closest first.
    def in_reach(payment)
      distance = ->(invoice) { (payment.date - invoice[:due]).abs }
      @invoices.select { |invoice| distance.call(invoice) <= WINDOW }.sort_by(&distance)
    end

    def matching(invoices, amount)
      invoices.find { |invoice| invoice[:total] == amount }
    end

    def settle(invoice, payment, second = nil)
      @invoices.delete(invoice)
      invoice[:charges].update_all(settled_by_id: payment.id) # rubocop:disable Rails/SkipsModelValidations
      return 1 if second.nil?

      Transaction.where(id: second.id).update_all(transfer_id: payment.transfer_id) # rubocop:disable Rails/SkipsModelValidations
      2
    end

    # Every invoice of the user's cards whose charges are all settled, with
    # what it billed and when it was due.
    def settled_invoices
      user = @payments.first.user
      user.credit_cards.flat_map do |card|
        months = card.transactions.group(:invoice_month).having("bool_and(transactions.paid)").charged_total
        months.map do |month, total|
          { charges: card.transactions.where(invoice_month: month), total:,
            due: Date.new(month.year, month.month, [card.due_day, month.end_of_month.day].min) }
        end
      end
    end
  end
end
