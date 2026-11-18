defmodule Mix.Tasks.Kairos.Explain do
  use Mix.Task
  @shortdoc "Explains one Kairos finding"

  def run([id]) do
    Mix.Task.run("app.start")

    case Kairos.Store.finding(String.to_integer(id)) do
      {:ok, finding} ->
        rule = Kairos.Rules.fetch(finding.field)

        Mix.shell().info(
          "#{finding.cause} #{finding.service}.#{finding.field}\n#{rule.rationale}\nDeclared: #{finding.declared}\nActual: #{finding.actual}\nAttribution unavailable unless correlated with external host or CI audit logs."
        )

      {:error, reason} ->
        Mix.raise("Kairos explain failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix kairos.explain <finding_id>")
end
