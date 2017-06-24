defmodule CardLabeler.Models.IssueCard do
  # issue["number"] as key
  defstruct [:id, :state, :labels, :column, :card_id]
end
