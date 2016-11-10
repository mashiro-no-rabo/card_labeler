use Mix.Config

# Configures your GitHub username and a Personal Access Token (with `repo` scope)
# ref: https://github.com/settings/tokens
config :card_labeler, CardLabeler.GitHub,
  token: "sample:sample_token"

# Configures a list of tuples in the format of
# {repo, project_id, default_column_id}
# You can get the column ids via https://api.github.com/repos/:owner/:repo/projects/:project_id/columns
config :card_labeler, CardLabeler,
  worker_configs: [
    {"owner/repo", 1, 42},
  ]

# Configures the interval between worker updates
config :card_labeler, CardLabeler.Worker,
  interval: 120

import_config "secrets.exs"
