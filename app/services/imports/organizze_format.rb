module Imports
  # Shape of an Organizze "movimentações" export, shared by the analyzer that
  # reads it and the importer that writes it.
  #
  # One worksheet per source, named as it is in Organizze; the ones suffixed
  # "- Cartão" are credit cards. Every sheet has the same header row:
  #
  #   Data | Descrição | Categoria | Valor | Situação | Tags | Informações adicionais
  module OrganizzeFormat
    CARD_SUFFIX = /\s*-\s*cart(?:ã|a)o\s*\z/i
    MONTHS = %w[janeiro fevereiro março abril maio junho
                julho agosto setembro outubro novembro dezembro].freeze
    SETTLED = "Pago".freeze

    DATE = 0
    DESCRIPTION = 1
    CATEGORY = 2
    AMOUNT = 3
    STATUS = 4
    NOTES = 6

    module_function

    def card_sheet?(name)
      name.match?(CARD_SUFFIX)
    end

    def parse_date(value)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

      Date.strptime(value.to_s.strip, "%d.%m.%Y")
    rescue ArgumentError, TypeError
      nil
    end

    # "Setembro/2026" -> Date.new(2026, 9, 1). On a card row this is the invoice
    # the charge belongs to, named after the month it is DUE.
    def parse_invoice_month(value)
      name, year = value.to_s.strip.split("/")
      index = MONTHS.index(name.to_s.downcase)
      return nil if index.nil? || year.blank?

      Date.new(year.to_i, index + 1, 1)
    end
  end
end
