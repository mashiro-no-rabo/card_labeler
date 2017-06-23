defmodule CardLabeler.TeslaMiddleWare.BackoutRetry do
  @moduledoc """
  Tesla middleware for retrying with backout delay,
  also retry on non 200 responses.
  """
  alias Tesla.Error, as: TeslaError

  @default_backout_list Enum.map(1..4, &(500 * &1))

  def call(env, next, opts) do
    backout_list = opts || @default_backout_list

    backout_retry(env, next, backout_list)
  end

  defp backout_retry(env, next, []) do
    Tesla.run(env, next)
  end

  defp backout_retry(env, next, [delay | rest]) do
    try do
      resp = Tesla.run(env, next)
      if resp.status < 200 or resp.status > 299 do
        backout_retry(env, next, rest)
      else
        resp
      end
    rescue
      _ in TeslaError ->
        :timer.sleep(delay)
        backout_retry(env, next, rest)
      e ->
        reraise e, System.stacktrace
    end
  end
end
