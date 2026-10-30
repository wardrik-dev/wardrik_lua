# WardrikLua

Lua 5.3 for agents. The `run_lua` tool runs code an agent writes in a sealed sandbox and returns
the value. Agents use it for work no other tool covers: arithmetic, reshaping data, loops, or the
current time.

```elixir
def deps do
  [
    {:wardrik_lua, "~> 0.1.0-rc.1"}
  ]
end
```

## Usage

Give agents the capability:

```elixir
WardrikCore.start_agent(
  agent_id: "acme/triage",
  model: "anthropic:claude-haiku-4-5",
  capabilities: [WardrikLua]
)
```

In [Wardrik](https://hexdocs.pm/wardrik), offer it by name. A definition then names it in its
`tools`:

```elixir
config :my_app, MyApp.AgentRuntime, capabilities: [run_lua: WardrikLua]
```

The daemon already offers it as `run_lua`.

## The sandbox

The VM is [lua](https://hexdocs.pm/lua), written in Elixir. It can't reach anything outside itself.

* Available: `string`, `table`, `math`, `utf8`, `os.time`, `os.date` and the rest of `os` that
  touches nothing outside.
* Raise when called: `io`, `file`, `os.execute`, `os.exit`, `os.getenv`, `package`, `require`,
  `load`, `dofile`, `print` and `debug`.

Each run is evaluated in a task of its own, under `WardrikLua.Sandbox.Limits`:

| Limit | Default |
| --- | --- |
| `:timeout_ms` | 30 seconds |
| `:max_heap_bytes` | 64 MB |
| `:max_steps` | 10 million |
| `:max_depth` | 200 nested calls |

Pass `:limits` to change them:

```elixir
{WardrikLua, limits: [timeout_ms: :timer.seconds(5)]}
```
