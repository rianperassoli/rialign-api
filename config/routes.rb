Rails.application.routes.draw do
  # Liveness/readiness probe (no auth).
  get "up", to: "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Authentication
      post "auth/register", to: "authentication#register"
      post "auth/login",    to: "authentication#login"
      get  "auth/me",       to: "authentication#me"

      resources :accounts, except: %i[new edit]
      resources :credit_cards, except: %i[new edit]
      resources :categories, except: %i[new edit]
      resources :transactions, except: %i[new edit]

      # Dashboard / consolidated views
      get "dashboard",          to: "dashboard#show"
      get "dashboard/balances", to: "dashboard#balances"
    end
  end
end
