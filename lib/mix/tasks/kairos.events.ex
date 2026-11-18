defmodule Mix.Tasks.Kairos.Events do
  use Mix.Task
  @shortdoc "Records recent Docker lifecycle events"

  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, strict: [since: :integer])
    since = System.system_time(:second) - (opts[:since] || 60)

    with {:ok, events} <- Kairos.Collector.Docker.events(since),
         :ok <-
           Kairos.Store.record_events(
             Enum.filter(
               events,
               &(Map.get(&1, "Action") in [
                   "create",
                   "start",
                   "die",
                   "update",
                   "destroy",
                   "rename"
                 ])
             )
           ) do
      Mix.shell().info("Recorded #{length(events)} lifecycle event(s).")
    else
      {:error, reason} -> Mix.raise("Kairos events failed: #{inspect(reason)}")
    end
  end
end
