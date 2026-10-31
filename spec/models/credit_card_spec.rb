require "rails_helper"

RSpec.describe CreditCard, type: :model do
  subject(:credit_card) { build(:credit_card) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:payment_account).optional }
  it { is_expected.to have_many(:transactions).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }

  it "accepts a payment account owned by the same user" do
    user = create(:user)
    expect(build(:credit_card, user:, payment_account: create(:account, user:))).to be_valid
  end

  it "rejects a payment account owned by another user" do
    card = build(:credit_card, user: create(:user), payment_account: create(:account))
    expect(card).to be_invalid
    expect(card.errors[:payment_account]).to include("must belong to the same user")
  end

  it "rejects a negative credit limit" do
    expect(build(:credit_card, credit_limit: -1)).to be_invalid
  end

  it "rejects out-of-range closing/due days" do
    expect(build(:credit_card, closing_day: 0)).to be_invalid
    expect(build(:credit_card, due_day: 32)).to be_invalid
  end

  # Each charge sits on one invoice (named after the month it is due). The open
  # invoice is everything still pending up to the invoice accumulating charges
  # today; later invoices are the next one. Both consume the limit.
  describe "invoice and limit" do
    subject(:card) { create(:credit_card, user:, closing_day: 20, due_day: 1, credit_limit: 1000) }

    let(:user) { create(:user) }
    let(:category) { create(:category, user:) }

    def charge(amount, date, paid: false, invoice_month: nil)
      create(:transaction, user:, category:, account: nil, credit_card: card, amount:, date:, paid:, invoice_month:)
    end

    # Closing on the 20th, due on the 1st: on 15/05 the invoice accumulating
    # charges is the one closing on 20/05, due in June.
    before { travel_to Date.new(2026, 5, 15) }

    it "names the current invoice after the month it is due" do
      expect(card.current_invoice_month).to eq(Date.new(2026, 6, 1))
    end

    it "counts pending charges on the current invoice" do
      charge(100, Date.new(2026, 5, 10))
      expect(card.open_invoice).to eq(100)
    end

    it "still counts pending charges left over from an earlier invoice" do
      charge(100, Date.new(2026, 2, 5))
      expect(card.open_invoice).to eq(100)
    end

    it "excludes charges on later invoices" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      expect(card.open_invoice).to eq(100)
    end

    it "moves on to the next invoice once the closing day has passed" do
      travel_to Date.new(2026, 5, 25)
      charge(100, Date.new(2026, 5, 22))
      expect(card.current_invoice_month).to eq(Date.new(2026, 7, 1))
      expect(card.open_invoice).to eq(100)
    end

    it "excludes charges already settled" do
      charge(100, Date.new(2026, 5, 10), paid: true)
      expect(card.open_invoice).to eq(0)
    end

    it "nets pending credits against the invoice and the limit they sit on" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      create(:transaction, user:, kind: "income", category: create(:income_category, user:),
                           account: nil, credit_card: card, amount: 30, date: Date.new(2026, 5, 12), paid: false)

      expect(card.open_invoice).to eq(70)
      expect(card.next_invoice).to eq(70)
      expect(card.available_limit).to eq(860)
    end

    it "gathers charges on later invoices into the next invoice" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      expect(card.next_invoice).to eq(70)
    end

    it "keeps a charge pushed to a later invoice off the current one" do
      charge(100, Date.new(2026, 5, 10), invoice_month: Date.new(2026, 7, 1))
      expect(card.open_invoice).to eq(0)
      expect(card.next_invoice).to eq(100)
    end

    it "leaves the next invoice empty when nothing sits on a later invoice" do
      charge(100, Date.new(2026, 5, 10))
      expect(card.next_invoice).to eq(0)
    end

    it "consumes the limit with every pending charge, later invoices included" do
      charge(100, Date.new(2026, 5, 10))
      charge(70, Date.new(2026, 5, 25))
      expect(card.used_limit).to eq(170)
      expect(card.available_limit).to eq(830)
    end
  end

  describe "#invoice_due" do
    let(:user) { create(:user) }
    # Closes on the 31st, due on the 4th: November's invoice takes October.
    let(:card) { create(:credit_card, user:, closing_day: 31, due_day: 4) }

    def charge(amount, invoice, paid: false)
      create(:transaction, user:, account: nil, credit_card: card, amount:, paid:, date: invoice << 1,
                           invoice_month: invoice)
    end

    before do
      charge(100, Date.new(2026, 10, 1), paid: true)
      charge(80, Date.new(2026, 11, 1))
      charge(30, Date.new(2026, 12, 1))
    end

    it "is the oldest invoice still owed, open while it takes purchases, with the one after it" do
      travel_to Date.new(2026, 10, 20) do
        expect(card.invoice_due).to include(month: "2026-11", due_date: Date.new(2026, 11, 4), amount: 80,
                                            status: "open")
        expect(card.invoice_after_due).to eq(month: "2026-12", amount: 30)
      end
    end

    it "stays on that invoice once it closes and after it is due, until it is paid" do
      travel_to(Date.new(2026, 11, 2)) { expect(card.invoice_due).to include(month: "2026-11", status: "closed") }
      travel_to(Date.new(2026, 11, 9)) { expect(card.invoice_due).to include(month: "2026-11", status: "overdue") }
    end

    it "moves on to the next invoice once it is paid, and is nil when nothing is owed" do
      card.transactions.where(invoice_month: Date.new(2026, 11, 1)).update_all(paid: true) # rubocop:disable Rails/SkipsModelValidations
      travel_to Date.new(2026, 11, 2) do
        expect(card.reload.invoice_due).to include(month: "2026-12", amount: 30, status: "open")
        expect(card.invoice_after_due).to eq(month: "2027-01", amount: 0)
      end

      card.transactions.update_all(paid: true) # rubocop:disable Rails/SkipsModelValidations
      expect(card.reload.invoice_due).to be_nil
      expect(card.invoice_after_due[:amount]).to eq(0)
    end
  end

  describe "#invoice_month_for" do
    it "bills a cycle in the month after it closes when due before the closing day" do
      card = build(:credit_card, closing_day: 31, due_day: 10)
      expect(card.invoice_month_for(Date.new(2026, 9, 30))).to eq(Date.new(2026, 10, 1))
      expect(card.invoice_month_for(Date.new(2026, 10, 1))).to eq(Date.new(2026, 11, 1))
    end

    it "bills a cycle in the month it closes when due after the closing day" do
      card = build(:credit_card, closing_day: 5, due_day: 20)
      expect(card.invoice_month_for(Date.new(2026, 10, 5))).to eq(Date.new(2026, 10, 1))
      expect(card.invoice_month_for(Date.new(2026, 10, 6))).to eq(Date.new(2026, 11, 1))
    end
  end

  it "soft deletes" do
    card = create(:credit_card)
    card.destroy
    expect(card.reload).to be_archived
  end
end
