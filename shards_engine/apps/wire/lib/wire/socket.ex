defmodule Wire.Socket do
  @moduledoc """
  One connection per client (spec §11). Connect params carry the run scope
  and, optionally, a PC identity: character connections get `{:pc, id}`,
  everyone else spectates. Roles gate channel joins in `RunChannel`.
  """

  use Phoenix.Socket

  # Channels are attached in their plan tasks; the socket is stable.

  @impl true
  def connect(%{"run_id" => run_id} = params, socket, _connect_info)
      when is_binary(run_id) and run_id != "" do
    role =
      case params["character_id"] do
        char_id when is_binary(char_id) and char_id != "" -> {:pc, char_id}
        _ -> :spectate
      end

    {:ok, assign(socket, run_id: run_id, role: role)}
  end

  def connect(_params, _socket, _connect_info), do: {:error, :missing_run_id}

  @impl true
  def id(socket) do
    case socket.assigns.role do
      {:pc, char_id} -> "run:#{socket.assigns.run_id}:pc:#{char_id}"
      :spectate -> "run:#{socket.assigns.run_id}:spectate:#{inspect(self())}"
    end
  end
end
