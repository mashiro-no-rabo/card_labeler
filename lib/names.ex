defmodule CardLabeler.Names do
  @moduledoc """
  Helper functions to compose via tuples for different parts of workers.

  All names are registered using `CardLabeler.Registry`.
  """

  @typep via_tuple :: {:via, atom, {String.t, atom}}

  @spec repo_sup(String.t) :: via_tuple
  def repo_sup(repo) do
    {:via, Registry, {CardLabeler.Registry, {repo, :supervisor}}}
  end

  @spec repo_storage(String.t) :: via_tuple
  def repo_storage(repo) do
    {:via, Registry, {CardLabeler.Registry, {repo, :storage}}}
  end

  @spec repo_tracker(String.t) :: via_tuple
  def repo_tracker(repo) do
    {:via, Registry, {CardLabeler.Registry, {repo, :tracker}}}
  end

  @spec repo_task_sup(String.t) :: via_tuple
  def repo_task_sup(repo) do
    {:via, Registry, {CardLabeler.Registry, {repo, :task_sup}}}
  end
end
