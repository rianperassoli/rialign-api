# The starter categories, as Organizze ships them, each with its icon and
# colour. A new account gets them (Categories::SeedDefaults), and an import
# dresses the categories it brings in the same way when their names match
# (Imports::OrganizzeImport), so Organizze's own categories arrive with icons.
#
# Icons are names from the web app's icon set (Lucide), which draws them.
module CategoryPresets
  LIST = {
    "expense" => {
      "Alimentação" => %w[utensils #e57373],
      "Assinaturas e serviços" => %w[receipt #ba68c8],
      "Bares e restaurantes" => %w[wine #5b5f8f],
      "Casa" => %w[house #818cf8],
      "Compras" => %w[shopping-bag #e879f9],
      "Cuidados pessoais" => %w[user #ef5350],
      "Dívidas e empréstimos" => %w[landmark #f87171],
      "Educação" => %w[graduation-cap #5c6bc0],
      "Família e filhos" => %w[heart #aed581],
      "Impostos e Taxas" => %w[percent #ff8a65],
      "Investimentos" => %w[chart-column #f06292],
      "Lazer e hobbies" => %w[smile #c0ca33],
      "Mercado" => %w[shopping-cart #ff7043],
      "Outros" => %w[ellipsis #9e9e9e],
      "Pets" => %w[paw-print #ffb74d],
      "Presentes e doações" => %w[gift #7c6cf2],
      "Roupas" => %w[shirt #ff8a65],
      "Saúde" => %w[cross #64b5f6],
      "Trabalho" => %w[briefcase #3f51b5],
      "Transporte" => %w[bus #4fc3f7],
      "Viagem" => %w[plane #ef5350]
    },
    "income" => {
      "Empréstimos" => %w[dollar-sign #34d399],
      "Investimentos" => %w[trending-up #34d399],
      "Outras receitas" => %w[ellipsis #34d399],
      "Salário" => %w[star #34d399]
    }
  }.freeze

  module_function

  # { icon:, color: } for a category named like a preset of its kind
  # (ignoring case and accents), or {} when none is.
  def for(name, kind)
    key = normalize(name)
    match = LIST.fetch(kind.to_s, {}).find { |preset, _| normalize(preset) == key }
    match ? { icon: match[1][0], color: match[1][1] } : {}
  end

  def normalize(name)
    I18n.transliterate(name.to_s.strip).downcase
  end
end
