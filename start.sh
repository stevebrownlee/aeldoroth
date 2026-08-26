#!/usr/bin/env bash
# Start the Shards Engine web platform (referee console + player seats).
#
# Usage:
#   ./start.sh              # offline NPCs (deterministic, fast declares)
#   ./start.sh --llm        # live LLM deliberation via $ANTHROPIC_API_KEY
#   PORT=4001 ./start.sh    # custom port (default 4000)
#
# Then open http://localhost:4000
#   - Lobby:        /           (Launch Game as GM)
#   - Player seat:  /runs/<run_id>?pc=<pc_id>  (join URL from lobby)
#   - GM console:   /runs/<run_id>/gm

set -euo pipefail

cd "$(dirname "$0")/shards_engine"

PORT="${PORT:-4000}"
export PORT

# Default: unset the key so the LLM gateway has no route and brains use the
# deterministic offline heuristic. A configured-but-unreachable key costs a
# 10s adapter timeout on every declare/deliberate.
UNSET_KEY=1
if [[ "${1:-}" == "--llm" ]]; then
  UNSET_KEY=0
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "error: mix not found — install Elixir (brew install elixir)" >&2
  exit 1
fi

if [[ -n "$(lsof -ti :"$PORT" 2>/dev/null)" ]]; then
  echo "error: port $PORT already in use — stop the running server first:" >&2
  echo "  lsof -ti :$PORT | xargs kill" >&2
  exit 1
fi

mix local.hex --force --if-missing >/dev/null
mix deps.get
mix compile

if [[ "$UNSET_KEY" -eq 1 ]]; then
  unset ANTHROPIC_API_KEY
fi

echo "[start.sh] serving http://localhost:$PORT (mode: $([[ "$UNSET_KEY" -eq 1 ]] && echo offline-deterministic || echo live-llm))"
exec mix run --no-halt scripts/web_server.exs
