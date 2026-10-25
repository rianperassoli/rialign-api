namespace :recurrences do
  desc "Create the next occurrences of every open-ended fixed entry (12 months ahead)"
  task extend: :environment do
    Recurrences::Extend.due
  end
end
