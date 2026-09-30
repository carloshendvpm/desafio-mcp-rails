Rails.application.routes.draw do
  # GET / serve public/index.html (página de demo)
  post "ask" => "ask#create"
  get "tools" => "ask#tools"

  get "up" => "rails/health#show", as: :rails_health_check
end
