require "pagy/extras/headers"
require "pagy/extras/overflow"

# Default page size for index endpoints; clients may override with ?items=.
Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:max_limit] = 100
Pagy::DEFAULT[:overflow] = :last_page
