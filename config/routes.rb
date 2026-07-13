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
      resources :credit_cards, except: %i[new edit] do
        member do
          get  :invoice
          post :pay_invoice
        end
      end
      resources :categories, except: %i[new edit]
      resources :transactions, except: %i[new edit]
      # :id is the shared transfer_id (a uuid); transfers are create/list/delete
      # only — editing is delete + recreate.
      resources :transfers, only: %i[index create destroy]

      # Dashboard / consolidated views
      get "dashboard",          to: "dashboard#show"
      get "dashboard/balances", to: "dashboard#balances"

      # Historical reports (monthly evolution + category breakdown)
      get "reports", to: "reports#show"
    end
  end
end
