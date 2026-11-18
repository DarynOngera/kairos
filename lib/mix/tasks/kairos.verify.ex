defmodule Mix.Tasks.Kairos.Verify do
  use Mix.Task
  @shortdoc "Verifies the Kairos snapshot hash chain"

  def run(_args) do
    Mix.Task.run("app.start")

    case Kairos.Store.verify() do
      :ok -> Mix.shell().info("Kairos snapshot hash chain is valid.")
      {:error, reason} -> Mix.raise("Kairos verification failed: #{inspect(reason)}")
    end
  end
end
