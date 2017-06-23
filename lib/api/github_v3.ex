defmodule CardLabeler.GitHubV3 do
  use Tesla

  @token "Basic " <> Base.encode64(Application.get_env(:card_labeler, CardLabeler.GitHub)[:token])

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, %{
    "Accept" => "application/vnd.github.inertia-preview+json",
    "User-Agent" => "card_labeler",
    "Authorization" => @token,
  }
  plug Tesla.Middleware.JSON
  plug CardLabeler.TeslaMiddleWare.BackoutRetry
  plug Tesla.Middleware.DebugLogger

  adapter Tesla.Adapter.Hackney

  def get_columns(project_id) do
    get("/projects/#{project_id}/columns")
    |> Map.get(:body)
    |> Enum.map(fn column -> {column["id"], column["name"]} end)
    |> Enum.into(%{})
  end

  def get_issues(repo, last_update), do: do_get_issues(repo, last_update, 1, [])
  defp do_get_issues(repo, last_update, page, acc) do
    resp = build_issues_url(repo, last_update, page) |> get()
    new_acc = acc ++ resp.body

    if has_next_page?(resp),
      do: do_get_issues(repo, last_update, page+1, new_acc),
      else: new_acc
  end

  def get_cards(column_id), do: do_get_cards(column_id, 1, [])
  defp do_get_cards(column_id, page, acc) do
    resp = get("/projects/columns/#{column_id}/cards?page=#{page}")
    cards = Enum.filter(resp.body, fn card ->
      Map.has_key?(card, "content_url") and String.contains?(card["content_url"], "/issues/")
    end)
    new_acc = acc ++ cards

    if has_next_page?(resp),
      do: do_get_cards(column_id, page+1, new_acc),
      else: new_acc
  end

  defp build_issues_url(repo, nil, page), do: "/repos/#{repo}/issues?per_page=100&page=#{page}&state=all"
  defp build_issues_url(repo, last_update, page), do: "/repos/#{repo}/issues?per_page=100&page=#{page}&state=all&since=#{last_update}"

  defp has_next_page?(response) do
    response.headers
    |> Map.get("link", "")
    |> String.contains?("rel=\"next\"")
  end

  def move_card(card_id, col_id), do: post("/projects/columns/cards/#{card_id}/moves", %{position: "top", column_id: col_id})
  def add_card(column_id, issue_id) do
    post(
      "/projects/columns/#{column_id}/cards",
      %{content_id: issue_id, content_type: "Issue"}
    )
    |> Map.get(:body)
    |> Map.get("id")
  end

  def remove_label(repo, issue_num, label),
    do: delete("/repos/#{repo}/issues/#{issue_num}/labels/#{URI.encode(label)}")

  def add_label(repo, issue_num, label),
    do: post("/repos/#{repo}/issues/#{issue_num}/labels", [label])

  def close_issue(repo, issue_num) do
    patch(
      "/repos/#{repo}/issues/#{issue_num}",
      %{state: "closed"}
    )
  end
end
