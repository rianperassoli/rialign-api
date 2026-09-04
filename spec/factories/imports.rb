FactoryBot.define do
  factory :import do
    user
    status { "pending" }
    filename { "movimentacoes.xls" }
    file_path { Rails.root.join("tmp/imports/example.xls").to_s }
  end
end
