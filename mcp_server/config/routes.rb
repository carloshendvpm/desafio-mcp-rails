Rails.application.routes.draw do
  post "mcp" => "mcp#handle"

  get "up" => "rails/health#show", as: :rails_health_check
end
