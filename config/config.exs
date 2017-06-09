use Mix.Config

# Configures your GitHub username and a Personal Access Token (with `repo` scope)
# ref: https://github.com/settings/tokens
config :card_labeler, CardLabeler.GitHub,
  token: "sample:sample_token"

# Configures a list of tuples in the format of
# {repo, project_id, new_col, close_col}
# You can get project ids via https://api.github.com/repos/:owner/:repo/projects
# You can get the column ids via https://api.github.com/projects/:project_id/columns
config :card_labeler, CardLabeler.ReposSupervisor,
  repo_configs: [
    {"owner/repo", 1, 42, 24},
  ]

# Configures the interval between worker updates
config :card_labeler, CardLabeler.Worker,
  interval: 60

# Provide your configs to overwrite in "secrets.exs"
import_config "secrets.exs"
