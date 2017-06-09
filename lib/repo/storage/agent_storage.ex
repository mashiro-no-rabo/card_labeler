defmodule CardLabeler.Repo.AgentStorage do
  @moduledoc """
  Use an `Agent` to store issue and card states.

  Also provides wrappers for update.
  """
  alias CardLabeler.Names

  def start_link({repo, _, _, _}) do
    Agent.start_link(&Map.new/0, name: Names.repo_storage(repo))
  end

  ## Wrappers
  def get(repo, key) do
    Agent.get(
      Names.repo_storage(repo),
      &(Map.get(&1, key))
    )
  end

  def get_all(repo) do
    Agent.get(Names.repo_storage(repo), &(&1))
  end

  def update(repo, key, initial, fun) do
    Agent.update(
      Names.repo_storage(repo),
      &(Map.update(&1, key, initial, fun))
    )
  end

  def update!(repo, key, fun) do
    Agent.update(
      Names.repo_storage(repo),
      &(Map.update!(&1, key, fun))
    )
  end
end
