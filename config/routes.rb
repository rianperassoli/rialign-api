Rails.application.routes.draw do
  # Liveness/readiness probe (no auth).
  get "up", to: "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Authentication
      post "auth/register", to: "authentication#register"
      post "auth/login",    to: "authentication#login"
      get  "auth/me",       to: "authentication#me"

      resources :imports, only: %i[index show create] do
        member { post :confirm }
      end
      resources :accounts, except: %i[new edit] do
        member { post :restore }
      end
      resources :credit_cards, except: %i[new edit] do
        member do
          get  :invoice
          post :pay_invoice
        end
      end
      resources :categories, except: %i[new edit]
      resources :transactions, except: %i[new edit] do
        # The filtered list as a CSV file, every page of it.
        get :export, on: :collection
      end
      # :id is the shared transfer_id (a uuid); show/update/destroy act on every
      # leg of the transfer together.
      resources :transfers, only: %i[index show create update destroy]

      # Dashboard / consolidated views
      get "dashboard",          to: "dashboard#show"
      get "dashboard/balances", to: "dashboard#balances"

      # Reports, as Organizze's: categories and money in x out over a period
      get "reports/cash_flow", to: "reports#cash_flow"
      get "reports/categories", to: "reports#categories"
    end
  end
end
