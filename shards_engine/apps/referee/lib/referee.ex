defmodule Referee do
  @moduledoc """
  The referee pipeline: propose → validate → resolve → apply → narrate
  (spec §7, decision 20 — LLM proposes, engine disposes).

  `Referee.Run` is the pure run container (world + rng + ledger + prefs +
  gateway ctx). Stages are pure functions over it; the OTP supervision
  tree (World.Server, Endpoint, brains) arrives with Plans 4–5. PC
  natural-language intent enters via `Referee.Run.declare/3`; engine
  truth changes only through `EngineCore.Fold`.
  """
end
