Rails.application.routes.draw do
  # Liveness only: Rails booted successfully. This does not query PostgreSQL.
  get "up" => "rails/health#show", as: :rails_health_check
end
