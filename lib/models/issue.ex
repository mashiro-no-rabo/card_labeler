defmodule CardLabeler.Models.Issue do
  # issue["number"] as key
  defstruct [:id, :state, :labels, :column, :card_id]
end
