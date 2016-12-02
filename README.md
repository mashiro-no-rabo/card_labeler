# CardLabeler

Makes using GitHub Project to manage GitHub Issues sane.

## Feature

This service periodically check Issues and Project updates, it will then perform actions in the following order:

1. Move closed issues to `close_col` if not already
2. Add issues to a column according to its label, or add to the default `new_col`
3. Cleanup and assign correct labels according to issue's column
  - This will not touch other labels if it's not a column name
4. Close any open issues in `close_col`

## Usage

Add your token and project config in `secrets.exs`, following the comments in `config.exs`, then run the project as normal.

## Misc

Originated for managing [this](https://github.com/ccpgames/esi-issues/projects/1) and [this](https://github.com/ccpgames/esi-issues/issues).
