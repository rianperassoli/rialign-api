module Imports
  # Rebuilds card installments from an Organizze export.
  #
  # The export has no installment columns: Organizze appends the parcel to the
  # description ("Tv pai 8/12") and lists each parcel as its own row, dated in
  # the month it is charged. Rialign keeps the parcel in `installment_number` /
  # `installment_total` with a shared `series_id`, which is what lets the
  # category breakdown count a purchase once (see
  # Transaction.purchased_between) and the series be edited together.
  #
  # Parcels belong to the same purchase when they share the card, the
  # description and the parcel count. Read in date order, each parcel follows
  # the purchase whose last parcel is the one before it; with none, it starts
  # a new purchase (the same thing bought twice runs as two series).
  class InstallmentSeries
    SUFFIX = %r{\A(?<description>.+?)\s+(?<number>\d{1,3})/(?<total>\d{1,3})\s*\z}

    # Row index => series id for each installment parcel on a card sheet.
    def self.for_sheet(sheet)
      rows = 1.upto(sheet.row_count - 1).filter_map do |i|
        row = sheet.row(i)
        date = OrganizzeFormat.parse_date(row[OrganizzeFormat::DATE])
        parcel = parcel(row)
        [i, date, parcel] if date && parcel
      end
      assign(rows)
    end

    # The parcel a card row is, or nil. Only a spending row is one: a credit or
    # an invoice payment that happens to end in "1/2" is not.
    def self.parcel(row)
      return if row[OrganizzeFormat::AMOUNT].to_f >= 0
      return if OrganizzeImport::TRANSFER_CATEGORIES.include?(row[OrganizzeFormat::CATEGORY].to_s.strip)

      parse(row[OrganizzeFormat::DESCRIPTION])
    end

    # The parcel a description names, or nil when it names none.
    def self.parse(description)
      match = SUFFIX.match(description.to_s.strip)
      return if match.nil?

      number = match[:number].to_i
      total = match[:total].to_i
      return unless total > 1 && number.between?(1, total)

      { description: match[:description], installment_number: number, installment_total: total }
    end

    # `rows` are [key, date, parcel] for one card's installment rows, where the
    # key tells the row apart (its index in the sheet). Returns key => series id.
    def self.assign(rows)
      rows.group_by { |_, _, parcel| parcel.values_at(:description, :installment_total) }
          .each_value.with_object({}) do |parcels, ids|
        series = []
        parcels.sort_by { |_, date, parcel| [date, parcel[:installment_number]] }.each do |key, _, parcel|
          number = parcel[:installment_number]
          current = series.find { |s| s[:number] == number - 1 }
          series << (current = { id: SecureRandom.uuid }) if current.nil?
          current[:number] = number
          ids[key] = current[:id]
        end
      end
    end
  end
end
