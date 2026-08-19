defmodule Wire.Socket do
  @moduledoc """
  One connection per client (spec §11). Connect params carry the run scope
  and, optionally, a PC identity: character connections get `{:pc, id}`,
  everyone else spectates. Roles gate channel joins in `RunChannel`.
  """

  use Phoenix.Socket

  channel "run:*", Wire.RunChannel
  channel "spectate:*", Wire.SpectateChannel
  @impl true
  def connect(%{"run_id" => run_id} = params, socket, _connect_info)
      when is_binary(run_id) and run_id != "" do
    character_id =
      case params["character_id"] do
        char_id when is_binary(char_id) and char_id != "" -> char_id
        _ -> nil
      end

    role = if character_id, do: :pc, else: :spectate
    {:ok, assign(socket, run_id: run_id, character_id: character_id, role: role)}
  end

  def connect(_params, _socket, _connect_info), do: {:error, :missing_run_id}

  @impl true
  def id(socket) do
    char = socket.assigns.character_id || "spectate"
    "#{socket.assigns.run_id}:#{char}"
  end
end
