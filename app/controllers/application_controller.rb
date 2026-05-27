class ApplicationController < ActionController::API
  include ApiResponders
  include ExceptionHandler
  include JwtAuthenticatable
end
