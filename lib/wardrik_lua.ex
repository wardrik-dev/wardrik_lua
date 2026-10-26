defmodule WardrikLua do
  @moduledoc """
  Lua 5.3 for agents: the `run_lua` tool, which runs code an agent writes in a sealed sandbox and
  hands back the value. It's how an agent does work no other tool covers: arithmetic over numbers
  it holds, reshaping a result, a loop, or the time now, with `os.time` and `os.date`.

      WardrikCore.start_agent(agent_id: "acme/triage", model: "...", capabilities: [WardrikLua])

  The VM is written in Elixir and reaches nothing outside itself: no files, no network, no
  environment, and nothing else the agent has. Each run is checked, then evaluated in a task of its
  own under `WardrikLua.Sandbox.Limits`: a deadline, a memory budget, a step budget and a call
  depth. Give `:limits` to change them:

      {WardrikLua, limits: [timeout_ms: :timer.seconds(5)]}

  Reach for this when agents need exact answers they'd otherwise work out in their heads.
  """

  @behaviour WardrikCore.Capability

  alias WardrikLua.Sandbox
  alias WardrikLua.Sandbox.Limits

  @description """
  Run a snippet of Lua 5.3 and get the value it returns.

  Use it for anything you'd otherwise work out by hand: arithmetic and statistics over numbers you hold, filtering or reshaping a list, parsing and formatting strings, a loop, a small simulation. Prefer it to doing the work in your head whenever being exactly right matters. It's also the way forward when no other tool fits.

  Write a chunk that ends in `return`, or nothing comes back. A table returns as an object, or as an array when its keys are 1..n. `string`, `table`, `math`, `utf8`, `os.time` and `os.date` are there: use `os.time` and `os.date` for the date and time now.

  Return JSON-compatible data: strings must be valid UTF-8, and functions and cyclic tables can't be returned. Object keys must be strings, numbers or booleans; they become strings and must stay unique.

  The VM is sealed: no files, no network, no environment, no `require`, and nothing else you have. Give it only self-contained work, with the data it needs written into the snippet.
  """

  @returned_nothing "the chunk ran and returned nothing; end it with `return <value>` to get a value back"

  @impl WardrikCore.Capability
  def tools(_context, opts) do
    limits = opts |> Keyword.get(:limits, []) |> Limits.new()

    [
      WardrikCore.Tool.new!(
        name: "run_lua",
        description: @description,
        schema: [
          code: [
            type: :string,
            required: true,
            doc: "The Lua chunk to run, ending in `return <value>`"
          ]
        ],
        run: fn %{code: code}, _context -> code |> Sandbox.run(limits) |> answer() end,
        annotations: [read_only: true, idempotent: true]
      )
    ]
  end

  defp answer({:ok, nil}), do: {:ok, %{value: nil, note: @returned_nothing}}
  defp answer({:ok, value}), do: {:ok, %{value: value}}
  defp answer({:error, message}), do: {:error, message}
end
