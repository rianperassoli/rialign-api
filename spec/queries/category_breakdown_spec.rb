require "rails_helper"

RSpec.describe CategoryBreakdown do
  subject(:rows) { described_class.new(user.transactions).call }

  let(:user) { create(:user) }
  let(:food) { create(:category, user:, name: "Alimentação", color: "#e67e22") }
  let(:market) { create(:category, user:, name: "Mercado", parent: food, color: nil) }
  let(:restaurant) { create(:category, user:, name: "Restaurante", parent: food) }
  let(:rent) { create(:category, user:, name: "Aluguel") }

  before do
    create(:transaction, user:, category: food, amount: 10)
    create(:transaction, user:, category: market, amount: 300)
    create(:transaction, user:, category: restaurant, amount: 90)
    create(:transaction, user:, category: rent, amount: 350)
    create(:income_transaction, user:, amount: 5000)
  end

  it "adds subcategories into their parent, biggest first, listing them for drill-down" do
    expect(rows).to eq([
                         { category_id: food.id, name: "Alimentação", color: "#e67e22", icon: nil, total: 400,
                           children: [{ category_id: market.id, name: "Mercado", total: 300 },
                                      { category_id: restaurant.id, name: "Restaurante", total: 90 }] },
                         { category_id: rent.id, name: "Aluguel", color: rent.color, icon: nil, total: 350,
                           children: [] }
                       ])
  end

  it "still counts spending on archived categories" do
    food.archive!
    expect(rows.first).to include(category_id: food.id, total: 400)
  end
end
