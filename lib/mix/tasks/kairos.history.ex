defmodule Mix.Tasks.Kairos.History do
  use Mix.Task
  @shortdoc "Lists Kairos finding history"

  def run(_args) do
    Mix.Task.run("app.start")

    case Kairos.Store.history() do
      {:ok, rows} ->
        Enum.each(
          rows,
          &Mix.shell().info(
            "#{&1["status"]} #{&1["service"]}.#{&1["field"]} #{&1["cause"]} first=#{&1["first_seen"]} last=#{&1["last_seen"]}"
          )
        )

      {:error, reason} ->
        Mix.raise("Kairos history failed: #{inspect(reason)}")
    end
  end
end
