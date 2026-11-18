defmodule Kairos.Comparator do
  @moduledoc "Classifies declared, deployed, and actual service state in contract order."

  alias Kairos.{Normalizer, Rules}

  @spec compare(map(), map() | nil, keyword()) :: [map()]
  def compare(declared, actual, opts \\ [])

  def compare(declared, nil, _opts),
    do: [finding(declared.service, "missing", "container", nil, nil, "lifecycle", "high")]

  def compare(declared, actual, opts) do
    labels = actual.labels || %{}

    cond do
      missing_compose_labels?(labels) ->
        [
          finding(
            declared.service,
            "out_of_band",
            "container",
            declared.service,
            actual.id,
            "security",
            "high"
          )
        ]

      Keyword.get(opts, :expected_hash) &&
          labels["com.docker.compose.config-hash"] != Keyword.get(opts, :expected_hash) ->
        [
          finding(
            declared.service,
            "stale_deployment",
            "config_hash",
            Keyword.get(opts, :expected_hash),
            labels["com.docker.compose.config-hash"],
            "lifecycle",
            "medium"
          )
        ] ++ image_findings(declared, actual, opts)

      true ->
        field_findings(declared, actual) ++ image_findings(declared, actual, opts)
    end
  end

  @spec unmanaged([map()], [String.t()]) :: [map()]
  def unmanaged(containers, project_networks) do
    Enum.flat_map(containers, fn container ->
      labels = Map.get(container, "Labels", %{})

      networks =
        container |> Map.get("NetworkSettings", %{}) |> Map.get("Networks", %{}) |> Map.keys()

      if not Map.has_key?(labels, "com.docker.compose.project") and
           Enum.any?(networks, &(&1 in project_networks)) do
        [
          finding(
            "(unmanaged)",
            "unmanaged_container",
            "container",
            project_networks,
            Map.get(container, "Id"),
            "security",
            "high"
          )
        ]
      else
        []
      end
    end)
  end

  defp field_findings(declared, actual) do
    Enum.flat_map(declared.fields, fn {field, expected} ->
      present? =
        field in declared.declared_fields ||
          (Normalizer.special_extra?(field) && non_default?(expected, actual.fields[field]))

      actual_value = comparable_actual(field, expected, actual.fields[field])

      if present? and expected != actual_value do
        rule = Rules.fetch(field)
        cause = if rule.mutable?, do: "in_place_mutation", else: "unexplained"

        [
          finding(
            declared.service,
            cause,
            field,
            expected,
            actual_value,
            rule.category,
            rule.severity
          )
        ]
      else
        []
      end
    end)
  end

  defp image_findings(declared, actual, opts) do
    case Keyword.get(opts, :declared_image_id) do
      declared_id when is_binary(declared_id) and declared_id != actual.image_id ->
        [
          finding(
            declared.service,
            "image_drift",
            "image",
            declared_id,
            actual.image_id,
            "image",
            "medium"
          )
        ]

      _ ->
        []
    end
  end

  defp missing_compose_labels?(labels),
    do:
      not (Map.has_key?(labels, "com.docker.compose.project") and
             Map.has_key?(labels, "com.docker.compose.service"))

  defp comparable_actual("environment", expected, actual) when is_map(actual),
    do: Map.take(actual, Map.keys(expected))

  defp comparable_actual(_field, _expected, actual), do: actual

  defp non_default?(expected, actual) when expected != actual,
    do: actual not in [nil, false, "", [], %{}]

  defp non_default?(_expected, _actual), do: false

  defp finding(service, cause, field, declared, actual, category, severity),
    do: %{
      service: service,
      cause: cause,
      field: field,
      declared: declared,
      actual: actual,
      category: category,
      severity: severity
    }
end
