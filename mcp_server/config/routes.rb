Rails.application.routes.draw do
  post "mcp" => "mcp#handle"
  match "mcp" => "mcp#method_not_allowed", via: [ :get, :delete ]

  get "up" => "rails/health#show", as: :rails_health_check
end
