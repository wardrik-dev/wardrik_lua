# WardrikLua

Lua 5.3 for agents: the `run_lua` tool, which runs code an agent writes in a sealed sandbox and
hands back the value. It's how an agent does what no other tool covers: arithmetic over numbers it
holds, reshaping a result, a loop, or the time now.

```elixir
def deps do
  [
    {:wardrik_lua, "~> 0.1"}
  ]
end
```

Give agents the capability:

```elixir
WardrikCore.start_agent(agent_id: "acme/triage", model: "anthropic:claude-haiku-4-5", capabilities: [WardrikLua])
```

Or, in a [Wardrik](https://hexdocs.pm/wardrik), offer it by name, and a definition names it in its
`tools`:

```elixir
config :my_app, MyApp.Wardrik, capabilities: [run_lua: WardrikLua]
```

The daemon offers it as `run_lua` already.

## The sandbox

The VM is [lua](https://hexdocs.pm/lua), written in Elixir. It reaches nothing outside itself:
`io`, `file`, `os.execute`, `os.getenv`, `require`, `load` and `debug` raise. `string`, `table`,
`math`, `utf8`, `os.time` and `os.date` are there. Each run is evaluated in a task of its own under
`WardrikLua.Sandbox.Limits`:

| Limit | Default |
| --- | --- |
| `:timeout_ms` | 30 seconds |
| `:max_heap_bytes` | 64 MB |
| `:max_steps` | 10 million |
| `:max_depth` | 200 nested calls |

```elixir
{WardrikLua, limits: [timeout_ms: :timer.seconds(5)]}
```
