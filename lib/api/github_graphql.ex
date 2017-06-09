defmodule CardLabeler.GitHubGraphQL do
  use Tesla

  @token "Basic " <> Base.encode64(Application.get_env(:card_labeler, CardLabeler.GitHub)[:token])

  plug Tesla.Middleware.BaseUrl, "https://api.github.com/graphql"
  plug Tesla.Middleware.Headers, %{
    "User-Agent" => "card_labeler",
    "Authorization" => @token
  }

  adapter Tesla.Adapter.Hackney
end
