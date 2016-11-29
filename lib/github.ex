defmodule CardLabeler.GitHub do
  use HTTPoison.Base

  @token "Basic " <> Base.encode64(Application.get_env(:card_labeler, __MODULE__)[:token])

  defp process_url(url) do
    "https://api.github.com" <> url
  end

  defp process_request_headers(headers) do
    headers ++ [
      {"Accept", "application/vnd.github.inertia-preview+json"},
      {"User-Agent", "card_labeler"},
      {"Authorization", @token}
    ]
  end

  defp process_response_body(body) do
    Poison.decode!(body)
  end

  defp process_headers(headers), do: Enum.into(headers, %{})
end
