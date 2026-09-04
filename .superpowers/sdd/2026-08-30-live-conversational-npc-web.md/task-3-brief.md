### Task 3: `.env` activation in the web server script

**Files:**
- Modify: `shards_engine/scripts/web_server.exs` (insert after line 8 `port = ...`; extend the `IO.puts` block at lines 25–30; append two private helpers at file end)

**Interfaces:**
- Consumes: `LLMGateway.Config.{apply_env_routing/0, live?/0, model/0}` (Task 1).
- Produces: server process env sourced from `shards_engine/.env` (per-var: explicit shell env wins), routing applied before any session can be created, one log line.

- [ ] **Step 1: Insert env sourcing after the `port =` line (line 8)**

Insert immediately after line 8 (`port = String.to_integer(System.get_env("PORT", "4000"))`):

```elixir
# LLM activation (spec 2026-08-30 §4.2): source shards_engine/.env (per-var,
# explicit shell env wins), then apply live routing — Run.new reads
# Application config lazily per run creation, so sessions created after this
# point go live with no server restart.
source_env_file(Path.expand(".env", __DIR__))
LLMGateway.Config.apply_env_routing()

routing_state =
  if LLMGateway.Config.live?() do
    "live (#{LLMGateway.Config.model()})"
  else
    "offline (set ANTHROPIC_API_KEY)"
  end
```

- [ ] **Step 2: Add the routing line to the boot banner**

Replace the `IO.puts("""` block (lines 25–30) with:

```elixir
IO.puts("""
[web_server] llm routing: #{routing_state}
[web_server] serving http://0.0.0.0:#{port}
[web_server] home (referee console):  /
[web_server] run seat:                /runs/<run_id>?pc=<pc_id>
[web_server] GM console:              /runs/<run_id>/gm
""")
```

- [ ] **Step 3: Append the `.env` parser helpers at file end**

Append after the final `:timer.sleep(:infinity)` line:

```elixir
# Plain KEY=VALUE lines (optional `export ` prefix — this repo's .env uses
# `export KEY=...`), `#` comments; outer matching quotes are stripped.
# A variable already present in the environment is never overwritten.
defp source_env_file(path) do
  if File.exists?(path) do
    path
    |> File.read!()
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.each(&put_env_line/1)
  end

  :ok
end

defp put_env_line(line) do
  case String.trim(line) do
    "" ->
      :ok

    "#" <> _ ->
      :ok

    trimmed ->
      trimmed = String.replace_prefix(trimmed, "export ", "")

      case :binary.split(trimmed, "=") do
        [key, value] ->
          key = String.trim(key)

          if key != "" and is_nil(System.get_env(key)) do
            System.put_env(key, strip_quotes(String.trim(value)))
          end

          :ok

        _ ->
          :ok
      end
  end
end

defp strip_quotes(<<q::utf8, rest::binary>>) when q in [?", ?'] do
  size = byte_size(rest)

  if size >= 1 and :binary.part(rest, size - 1, 1) == <<q>> do
    :binary.part(rest, 0, size - 1)
  else
    rest
  end
end

defp strip_quotes(value), do: value
```

- [ ] **Step 4: Verify the offline branch (shell wins over `.env`)**

`shards_engine/.env` exists and carries a real `ANTHROPIC_API_KEY`. Force the shell value to empty to prove precedence:

```bash
cd shards_engine && ANTHROPIC_API_KEY= MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Run in background; wait for the banner. Expected first banner line: `[web_server] llm routing: offline (set ANTHROPIC_API_KEY)`. Then stop the process.

- [ ] **Step 5: Verify the live branch (`.env` key activates routing)**

```bash
cd shards_engine && env -u ANTHROPIC_API_KEY MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Run in background; wait for the banner. Expected first banner line: `[web_server] llm routing: live (claude-haiku-4-5-20251001)` (or whatever `ANTHROPIC_MODEL` the `.env` sets). Then stop the process.

- [ ] **Step 6: Commit**

```bash
git add shards_engine/scripts/web_server.exs
git commit -m "feat(web): source .env and activate live routing at web server boot"
```

---

