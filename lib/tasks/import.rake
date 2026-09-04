namespace :import do
  desc "Import an Organizze .xls export: rake 'import:organizze[path,email,YYYY-MM]'"
  task :organizze, %i[path email open_from] => :environment do |_t, args|
    path = args[:path] or abort "Usage: rake 'import:organizze[path,email,YYYY-MM]'"
    user = User.find_by!(email: args[:email] || "demo@rialign.com")
    # Invoice month, named after the month it is due: every invoice from it
    # onward is imported as still open.
    open_from = args[:open_from].present? ? Date.strptime(args[:open_from], "%Y-%m") : Date.current.beginning_of_month

    result = Imports::OrganizzeImport.call(user: user, path: path, open_from: open_from)
    abort "Import failed: #{Array(result.errors).join(", ")}" if result.failure?

    r = result.data
    puts "Imported #{r[:imported]} transactions for #{user.email}"
    puts "  #{r[:accounts]} accounts, #{r[:credit_cards]} credit cards, #{r[:categories]} categories"
    puts "  skipped: #{r[:skipped_zero]} zero-amount, #{r[:skipped_card_credit]} card credits, " \
         "#{r[:skipped_no_date]} unparseable dates"
  end
end
