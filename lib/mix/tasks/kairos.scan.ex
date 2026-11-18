defmodule Mix.Tasks.Kairos.Scan do
  use Mix.Task

  @shortdoc "Scans one Docker Compose project for configuration drift"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, invalid} =
      OptionParser.parse(args, strict: [project: :string, file: :string, json: :boolean])

    if invalid != [] or is_nil(opts[:project]) or is_nil(opts[:file]) do
      Mix.raise("usage: mix kairos.scan --project <name> --file <compose.yml> [--json]")
    end

    with {:ok, key} <- Kairos.Store.fingerprint_key(),
         :ok <- Application.put_env(:kairos, :fingerprint_key, key),
         {:ok, state} <- Kairos.Scanner.scan_state(opts[:project], opts[:file]),
         {:ok, _snapshot_id} <-
           Kairos.Store.record(opts[:project], state.declared, state.actual, state.findings) do
      print(state.findings, opts[:json] == true)
    else
      {:error, reason} -> Mix.raise("Kairos scan failed: #{inspect(reason)}")
    end
  end

  defp print(findings, true), do: Mix.shell().info(JSON.encode!(findings))
  defp print([], false), do: Mix.shell().info("Kairos: no drift found.")
  defp print(findings, false), do: Enum.each(findings, &Mix.shell().info(format(&1)))

  defp format(finding),
    do:
      "#{finding.severity} #{finding.cause} #{finding.service}.#{finding.field}: declared=#{inspect(finding.declared)} actual=#{inspect(finding.actual)}"
end
