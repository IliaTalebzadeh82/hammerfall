Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health#ready"

  namespace :api do
    namespace :v1 do
      resources :users, only: %i[index create]
      resources :auctions, only: %i[index show create update] do
        member do
          get "public-state", to: "auctions#public_state"
          put "maximum-bid", to: "maximum_bids#update"
          post :schedule
          post :activate
          post :close
          post :cancel
        end
        resources :bids, only: %i[index create]
      end
    end
  end
end
