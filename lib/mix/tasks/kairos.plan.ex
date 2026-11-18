defmodule Mix.Tasks.Kairos.Plan do
  use Mix.Task
  @shortdoc "Prints a remediation plan without applying changes"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [project: :string, file: :string])

    if is_nil(opts[:project]) or is_nil(opts[:file]),
      do: Mix.raise("usage: mix kairos.plan --project <name> --file <compose.yml>")

    {:ok, findings} = Kairos.Scanner.scan(opts[:project], opts[:file])

    Enum.each(findings, fn finding ->
      Mix.shell().info(
        "PLAN ONLY: review #{finding.cause} for #{finding.service}.#{finding.field}; no Docker change will be made."
      )
    end)
  end
end
