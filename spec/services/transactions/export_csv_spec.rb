require "rails_helper"

RSpec.describe Transactions::ExportCsv do
  let(:user) { create(:user) }
  let(:account) { create(:account, user:, name: "NuBank") }
  let(:card) { create(:credit_card, user:, name: "NuBank - Cartão") }
  let(:food) { create(:category, user:, name: "Alimentação") }
  let(:market) { create(:category, user:, name: "Mercado", parent: food) }

  it "writes every entry oldest first, for Excel in Brazil" do
    salary = create(:income_transaction, user:, account:, description: "Salário", amount: 5000,
                                         date: Date.new(2026, 10, 5))
    create(:transaction, user:, account: nil, credit_card: card, category: market, description: "Feira",
                         amount: 123.4, date: Date.new(2026, 10, 2), paid: false)

    csv = described_class.new(user.transactions).call

    expect(csv).to start_with("﻿")
    expect(csv.delete_prefix("﻿").lines.map(&:chomp)).to eq(
      ["Data;Descrição;Categoria;Conta/Cartão;Valor;Situação",
       "02/10/2026;Feira;Alimentação › Mercado;NuBank - Cartão;-123,40;Não pago",
       "05/10/2026;Salário;#{salary.category.name};NuBank;5000,00;Pago"]
    )
  end

  it "leaves the category blank on a transfer" do
    create(:transaction, user:, account:, category: nil, transfer_id: SecureRandom.uuid, description: "Envio",
                         amount: 10, date: Date.new(2026, 10, 1))

    expect(described_class.new(user.transactions).call.lines.last.chomp).to eq("01/10/2026;Envio;;NuBank;-10,00;Pago")
  end
end
