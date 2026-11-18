defmodule Kairos.Normalizer do
  @moduledoc "Converts Compose and inspect payloads to comparable, secret-safe maps."

  alias Kairos.Fingerprint

  @fields ~w(read_only cap_add cap_drop privileged user security_opt ports networks dns environment volumes restart memory cpus pids_limit)
  @extra_fields ~w(cap_add privileged ports volumes)

  @spec declared(String.t(), map(), keyword()) :: map()
  def declared(service, compose, opts \\ []) do
    key = Keyword.get(opts, :fingerprint_key, Fingerprint.key())
    project = Keyword.get(opts, :project)

    fields = %{
      "read_only" => Map.get(compose, "read_only", false),
      "cap_add" => capabilities(Map.get(compose, "cap_add", [])),
      "cap_drop" => capabilities(Map.get(compose, "cap_drop", [])),
      "privileged" => Map.get(compose, "privileged", false),
      "user" => Map.get(compose, "user", ""),
      "security_opt" => string_set(Map.get(compose, "security_opt", [])),
      "ports" => declared_ports(Map.get(compose, "ports", [])),
      "networks" => declared_networks(Map.get(compose, "networks", []), project),
      "dns" => string_set(Map.get(compose, "dns", [])),
      "environment" => declared_env(Map.get(compose, "environment", %{}), key),
      "volumes" => declared_volumes(Map.get(compose, "volumes", [])),
      "restart" => restart(Map.get(compose, "restart")),
      "memory" =>
        memory(
          Map.get(compose, "mem_limit") ||
            get_in(compose, ["deploy", "resources", "limits", "memory"])
        ),
      "cpus" =>
        cpus(
          Map.get(compose, "cpus") || get_in(compose, ["deploy", "resources", "limits", "cpus"])
        ),
      "pids_limit" => pids(Map.get(compose, "pids_limit"))
    }

    declared_fields =
      Enum.filter(@fields, &Map.has_key?(compose, &1))
      |> Enum.concat(resource_declared(compose))
      |> Enum.uniq()

    %{
      service: service,
      image: Map.get(compose, "image"),
      fields: fields,
      declared_fields: declared_fields
    }
  end

  @spec actual(String.t(), map(), keyword()) :: map()
  def actual(service, inspect, opts \\ []) do
    key = Keyword.get(opts, :fingerprint_key, Fingerprint.key())
    config = Map.get(inspect, "Config", %{})
    host = Map.get(inspect, "HostConfig", %{})

    %{
      service: service,
      id: Map.get(inspect, "Id"),
      created_at: Map.get(inspect, "Created"),
      image_id: Map.get(inspect, "Image"),
      labels: Map.get(config, "Labels", %{}),
      fields: %{
        "read_only" => Map.get(host, "ReadonlyRootfs", false),
        "cap_add" => capabilities(Map.get(host, "CapAdd", [])),
        "cap_drop" => capabilities(Map.get(host, "CapDrop", [])),
        "privileged" => Map.get(host, "Privileged", false),
        "user" => Map.get(config, "User", ""),
        "security_opt" => string_set(Map.get(host, "SecurityOpt", [])),
        "ports" => actual_ports(Map.get(host, "PortBindings", %{})),
        "networks" =>
          inspect
          |> get_in(["NetworkSettings", "Networks"])
          |> Kernel.||(%{})
          |> Map.keys()
          |> Enum.sort(),
        "dns" => string_set(Map.get(host, "Dns", [])),
        "environment" => actual_env(Map.get(config, "Env", []), key),
        "volumes" => actual_volumes(Map.get(inspect, "Mounts", [])),
        "restart" => restart(Map.get(host, "RestartPolicy")),
        "memory" => null_if_zero(Map.get(host, "Memory", 0)),
        "cpus" => null_if_zero(Map.get(host, "NanoCpus", 0)),
        "pids_limit" => pids(Map.get(host, "PidsLimit"))
      }
    }
  end

  def special_extra?(field), do: field in @extra_fields

  defp resource_declared(compose) do
    []
    |> maybe(
      "memory",
      Map.has_key?(compose, "mem_limit") or
        not is_nil(get_in(compose, ["deploy", "resources", "limits", "memory"]))
    )
    |> maybe(
      "cpus",
      Map.has_key?(compose, "cpus") or
        not is_nil(get_in(compose, ["deploy", "resources", "limits", "cpus"]))
    )
  end

  defp maybe(list, value, true), do: [value | list]
  defp maybe(list, _value, false), do: list

  defp capabilities(values),
    do:
      values
      |> List.wrap()
      |> Enum.map(&(String.upcase(to_string(&1)) |> String.replace_prefix("CAP_", "")))
      |> Enum.uniq()
      |> Enum.sort()

  defp string_set(values),
    do: values |> List.wrap() |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

  defp null_if_zero(value) when value in [0, "0", nil], do: nil
  defp null_if_zero(value), do: value
  defp pids(value) when value in [0, -1, "0", "-1", nil], do: nil
  defp pids(value), do: value

  defp restart(nil), do: %{name: "no", max_retries: nil}
  defp restart(""), do: %{name: "no", max_retries: nil}
  defp restart(value) when is_binary(value), do: %{name: value, max_retries: nil}

  defp restart(value) do
    retries = Map.get(value, "MaximumRetryCount", Map.get(value, "max_retries"))

    %{
      name: Map.get(value, "Name", Map.get(value, "name", "no")),
      max_retries: if(retries in [0, "0"], do: nil, else: retries)
    }
  end

  defp memory(nil), do: nil
  defp memory(value) when is_integer(value), do: null_if_zero(value)

  defp memory(value) do
    case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)\s*([kmgt]?i?b?)?$/i, to_string(value)) do
      [_, numeric, unit] ->
        trunc(number(numeric) * memory_multiplier(String.downcase(unit)))

      _ ->
        value
    end
  end

  defp memory_multiplier(unit),
    do:
      %{
        "" => 1,
        "b" => 1,
        "k" => 1_024,
        "kb" => 1_024,
        "ki" => 1_024,
        "kib" => 1_024,
        "m" => 1_048_576,
        "mb" => 1_048_576,
        "mi" => 1_048_576,
        "mib" => 1_048_576,
        "g" => 1_073_741_824,
        "gb" => 1_073_741_824,
        "gi" => 1_073_741_824,
        "gib" => 1_073_741_824
      }[unit] || 1

  defp cpus(nil), do: nil
  defp cpus(value) when is_integer(value), do: value
  defp cpus(value), do: trunc(number(to_string(value)) * 1_000_000_000)

  defp number(value) do
    if String.contains?(value, "."), do: String.to_float(value), else: String.to_integer(value)
  end

  defp declared_env(env, key) when is_map(env),
    do:
      Map.new(env, fn {name, value} -> {name, Fingerprint.value(to_string(value || ""), key)} end)

  defp declared_env(env, key),
    do:
      env
      |> List.wrap()
      |> env_pairs()
      |> Map.new(fn {name, value} -> {name, Fingerprint.value(value, key)} end)

  defp actual_env(env, key),
    do:
      env |> env_pairs() |> Map.new(fn {name, value} -> {name, Fingerprint.value(value, key)} end)

  defp env_pairs(env),
    do:
      Enum.map(env, fn entry ->
        case String.split(to_string(entry), "=", parts: 2) do
          [name, value] -> {name, value}
          [name] -> {name, ""}
        end
      end)

  defp declared_networks(networks, project) when is_map(networks),
    do: networks |> Map.keys() |> normalize_networks(project)

  defp declared_networks(networks, project),
    do: networks |> List.wrap() |> Enum.map(&to_string/1) |> normalize_networks(project)

  defp normalize_networks(names, nil), do: Enum.sort(names)

  defp normalize_networks(names, project),
    do: names |> Enum.map(&"#{project}_#{&1}") |> Enum.sort()

  defp declared_ports(ports),
    do: ports |> List.wrap() |> Enum.flat_map(&port_from_declared/1) |> Enum.sort()

  defp port_from_declared(port) when is_map(port),
    do: [
      %{
        host_ip: Map.get(port, "host_ip", "0.0.0.0") |> blank_ip(),
        host_port: to_string(Map.get(port, "published", "")),
        container_port: to_string(Map.get(port, "target", "")),
        proto: Map.get(port, "protocol", "tcp")
      }
    ]

  defp port_from_declared(port) do
    parts = String.split(to_string(port), ":")

    {host_ip, host_port, target} =
      case parts do
        [target] -> {"0.0.0.0", "", target}
        [host, target] -> {"0.0.0.0", host, target}
        [ip, host, target] -> {ip, host, target}
      end

    [container_port, proto] = (String.split(target, "/", parts: 2) ++ ["tcp"]) |> Enum.take(2)

    [
      %{
        host_ip: blank_ip(host_ip),
        host_port: host_port,
        container_port: container_port,
        proto: proto
      }
    ]
  end

  defp actual_ports(bindings),
    do:
      bindings
      |> Enum.flat_map(fn {container, values} ->
        [container_port, proto] = String.split(container, "/", parts: 2)

        Enum.map(values || [], fn value ->
          %{
            host_ip: blank_ip(Map.get(value, "HostIp", "")),
            host_port: Map.get(value, "HostPort", ""),
            container_port: container_port,
            proto: proto || "tcp"
          }
        end)
      end)
      |> Enum.sort()

  defp blank_ip(""), do: "0.0.0.0"
  defp blank_ip(ip), do: ip

  defp declared_volumes(volumes),
    do: volumes |> List.wrap() |> Enum.map(&volume_declared/1) |> Enum.sort()

  defp volume_declared(volume) when is_map(volume),
    do: %{
      type: Map.get(volume, "type", "volume"),
      source: Map.get(volume, "source", ""),
      target: Map.get(volume, "target", ""),
      read_only: Map.get(volume, "read_only", false)
    }

  defp volume_declared(volume) do
    [source, target | rest] = String.split(to_string(volume), ":")

    %{
      type: if(String.starts_with?(source, "/"), do: "bind", else: "volume"),
      source: source,
      target: target,
      read_only: "ro" in rest
    }
  end

  defp actual_volumes(volumes),
    do:
      volumes
      |> Enum.map(fn volume ->
        %{
          type: Map.get(volume, "Type"),
          source: Map.get(volume, "Source", ""),
          target: Map.get(volume, "Destination", ""),
          read_only: Map.get(volume, "RW", true) == false
        }
      end)
      |> Enum.sort()
end
