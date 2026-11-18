defmodule Kairos.Scanner do
  @moduledoc false

  alias Kairos.{Collector.Compose, Collector.Docker, Comparator, Normalizer}

  @spec scan(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def scan(project, file) do
    with {:ok, state} <- scan_state(project, file), do: {:ok, state.findings}
  end

  @spec scan_state(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def scan_state(project, file) do
    with {:ok, config} <- Compose.config(project, file),
         {:ok, summaries} <- Docker.all_containers() do
      services = Map.get(config, "services", %{})

      states =
        Enum.map(services, fn {service, declaration} ->
          declared = Normalizer.declared(service, declaration, project: project)
          container = find_container(summaries, project, service)
          compare_service(declared, container, project, file, service)
        end)

      findings =
        states
        |> Enum.flat_map(& &1.findings)
        |> Kernel.++(Comparator.unmanaged(summaries, project_networks(config, project)))

      declared = Map.new(states, &{&1.service, &1.declared})
      actual = Map.new(states, &{&1.service, &1.actual})
      {:ok, %{findings: findings, declared: declared, actual: actual}}
    end
  end

  defp compare_service(declared, nil, _project, _file, service),
    do: %{
      service: service,
      declared: declared,
      actual: nil,
      findings: Comparator.compare(declared, nil, [])
    }

  defp compare_service(declared, summary, project, file, service) do
    with {:ok, inspect} <- Docker.inspect_container(Map.fetch!(summary, "Id")),
         {:ok, hash} <- Compose.hash(project, file, service) do
      actual = Normalizer.actual(service, inspect)
      image_id = declared_image_id(declared)

      %{
        service: service,
        declared: declared,
        actual: actual,
        findings:
          Comparator.compare(declared, actual, expected_hash: hash, declared_image_id: image_id)
      }
    else
      {:error, reason} ->
        %{
          service: service,
          declared: declared,
          actual: nil,
          findings: [
            %{
              service: service,
              cause: "collection_error",
              field: "container",
              declared: nil,
              actual: inspect(reason),
              category: "lifecycle",
              severity: "high"
            }
          ]
        }
    end
  end

  defp declared_image_id(%{image: image}) when is_binary(image) do
    case Docker.inspect_image(image) do
      {:ok, %{"Id" => id}} -> id
      _ -> nil
    end
  end

  defp declared_image_id(_declared), do: nil

  defp find_container(summaries, project, service) do
    Enum.find(summaries, &compose_container?(&1, project, service)) ||
      Enum.find(summaries, &expected_name?(&1, project, service))
  end

  defp compose_container?(summary, project, service) do
    labels = Map.get(summary, "Labels", %{})

    Map.get(labels, "com.docker.compose.project") == project and
      Map.get(labels, "com.docker.compose.service") == service
  end

  defp expected_name?(summary, project, service) do
    prefix = "#{project}-#{service}-"

    summary
    |> Map.get("Names", [])
    |> Enum.map(&String.trim_leading(&1, "/"))
    |> Enum.any?(&String.starts_with?(&1, prefix))
  end

  defp project_networks(config, project) do
    names = config |> Map.get("networks", %{}) |> Map.keys()

    if(names == [], do: ["default"], else: names)
    |> Enum.map(fn name ->
      if String.starts_with?(name, "#{project}_"), do: name, else: "#{project}_#{name}"
    end)
  end
end
