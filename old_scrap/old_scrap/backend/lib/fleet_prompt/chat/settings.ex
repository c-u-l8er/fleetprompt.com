defmodule FleetPrompt.Chat.Settings do
  @moduledoc """
  Runtime settings for chat behavior.

  We keep these in a single module so configuration is centralized and testable.
  """

  require Logger

  @default_tool_loop_max_rounds 6

  @doc """
  Maximum number of assistant/tool loop rounds allowed for a single `/chat/message` request.

  Resolution order:
  1. `CHAT_TOOL_LOOP_MAX_ROUNDS` environment variable (positive integer)
  2. `config :fleet_prompt, :chat, tool_loop_max_rounds: N`
  3. fallback to #{@default_tool_loop_max_rounds}
  """
  @spec tool_loop_max_rounds() :: pos_integer()
  def tool_loop_max_rounds do
    case System.get_env("CHAT_TOOL_LOOP_MAX_ROUNDS") do
      nil ->
        from_app_env()

      raw when is_binary(raw) ->
        case Integer.parse(String.trim(raw)) do
          {n, ""} when n > 0 ->
            n

          _ ->
            Logger.warning("[Chat] invalid CHAT_TOOL_LOOP_MAX_ROUNDS; falling back to app config",
              value: raw
            )

            from_app_env()
        end
    end
  end

  defp from_app_env do
    Application.get_env(:fleet_prompt, :chat, [])
    |> Keyword.get(:tool_loop_max_rounds, @default_tool_loop_max_rounds)
    |> normalize_pos_int(@default_tool_loop_max_rounds)
  end

  defp normalize_pos_int(n, fallback) when is_integer(n) and n > 0, do: n
  defp normalize_pos_int(_n, fallback), do: fallback
end
