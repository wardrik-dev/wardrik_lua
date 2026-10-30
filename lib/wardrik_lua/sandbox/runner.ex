defmodule WardrikLua.Sandbox.Runner do
  @moduledoc """
  Runs one evaluation in a task of its own, bounded by `WardrikLua.Sandbox.Limits`.

      WardrikLua.Sandbox.Runner.run(fn -> {:ok, 4} end, WardrikLua.Sandbox.Limits.new())
      #=> {:ok, 4}

  `WardrikLua.Sandbox.run/2` calls it. The VM implements the language; this module bounds the
  process.

  The task runs at low priority under its own task supervisor. It's killed when it passes its
  deadline, outgrows its memory budget, or its caller dies.

  ## Notes

    * The task isn't linked to its caller. The BEAM kills a process that outgrows its heap, and a
      link would pass that kill on to the waiting tool call. The caller monitors the task instead.
      The task supervisor is linked to the caller, so it takes the task down if the caller dies.
    * The heap cap is the BEAM's `:max_heap_size`. Off-heap binaries aren't counted by it, so they
      are polled every 50ms. Either budget can be overshot by one interval's work.
  """

  alias WardrikLua.Sandbox.Limits

  @typedoc "The function's result, or why it was stopped."
  @type result() :: {:ok, term()} | {:error, String.t()}

  @poll_interval_ms 50
  @out_of_memory "the code used more memory than it is allowed and was stopped"

  @doc "Runs `fun` under `limits`. Returns its result, or an error naming the limit that stopped it."
  @spec run((-> result()), Limits.t()) :: result()
  def run(fun, %Limits{} = limits) when is_function(fun, 0) do
    {:ok, supervisor} = Task.Supervisor.start_link()

    result =
      supervisor
      |> Task.Supervisor.async_nolink(fn -> evaluate(fun, limits) end)
      |> await(deadline(limits.timeout_ms), limits)

    :ok = Supervisor.stop(supervisor)
    result
  end

  defp evaluate(fun, limits) do
    Process.flag(:priority, :low)
    cap_heap(limits.max_heap_bytes)
    fun.()
  end

  defp cap_heap(:infinity), do: :ok

  defp cap_heap(bytes) do
    {:min_heap_size, minimum} = :erlang.system_info(:min_heap_size)
    words = max(div(bytes, :erlang.system_info(:wordsize)), minimum)
    Process.flag(:max_heap_size, %{size: words, kill: true, error_logger: false})
    :ok
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp await(task, deadline, limits) do
    case Task.yield(task, wait_ms(deadline, limits.max_heap_bytes)) do
      {:ok, result} -> result
      # Nothing else kills the task while its monitor is held, so a brutal
      # kill here is the BEAM enforcing the heap cap.
      {:exit, :killed} -> {:error, @out_of_memory}
      {:exit, reason} -> {:error, "the code crashed: #{inspect(reason)}"}
      nil -> stop_or_wait(task, deadline, limits)
    end
  end

  defp stop_or_wait(task, deadline, limits) do
    cond do
      past?(deadline) -> stop(task, timed_out(limits.timeout_ms))
      over_budget?(task.pid, limits.max_heap_bytes) -> stop(task, @out_of_memory)
      true -> await(task, deadline, limits)
    end
  end

  # An evaluation that finished between the check and the kill has an answer,
  # and an answer beats the limit it was about to be stopped for.
  defp stop(task, message) do
    case Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _stopped -> {:error, message}
    end
  end

  defp wait_ms(deadline, max_heap_bytes) do
    case {deadline, max_heap_bytes} do
      {:infinity, :infinity} -> :infinity
      {:infinity, _bytes} -> @poll_interval_ms
      {deadline, :infinity} -> remaining_ms(deadline)
      {deadline, _bytes} -> min(remaining_ms(deadline), @poll_interval_ms)
    end
  end

  defp remaining_ms(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp past?(:infinity), do: false
  defp past?(deadline), do: remaining_ms(deadline) == 0

  defp timed_out(ms), do: "the code ran for longer than #{ms}ms and was stopped"

  defp over_budget?(_pid, :infinity), do: false

  # A process can hold many references to the same binary, hence the uniq.
  defp over_budget?(pid, max_heap_bytes) do
    case Process.info(pid, :binary) do
      {:binary, held} ->
        held |> Enum.uniq_by(&elem(&1, 0)) |> Enum.sum_by(&elem(&1, 1)) > max_heap_bytes

      nil ->
        false
    end
  end
end
