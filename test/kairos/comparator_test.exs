defmodule Kairos.ComparatorTest do
  use ExUnit.Case, async: true

  alias Kairos.{Comparator, Normalizer}

  defp declared(overrides \\ %{}) do
    base = %{
      "mem_limit" => "512m",
      "privileged" => false,
      "cap_add" => [],
      "ports" => [],
      "environment" => %{"TOKEN" => "secret"}
    }

    Normalizer.declared("web", Map.merge(base, overrides), fingerprint_key: "test-key")
  end

  defp actual(overrides \\ %{}) do
    base = %{
      "Id" => "container-id",
      "Image" => "sha256:old",
      "Config" => %{
        "Env" => ["TOKEN=secret", "UNDECLARED=ignored"],
        "Labels" => %{
          "com.docker.compose.project" => "demo",
          "com.docker.compose.service" => "web",
          "com.docker.compose.config-hash" => "hash"
        }
      },
      "HostConfig" => %{
        "Memory" => 536_870_912,
        "Privileged" => false,
        "CapAdd" => [],
        "PortBindings" => %{}
      },
      "NetworkSettings" => %{"Networks" => %{}}
    }

    Normalizer.actual("web", deep_merge(base, overrides), fingerprint_key: "test-key")
  end

  test "reports missing services" do
    assert [%{cause: "missing", severity: "high"}] = Comparator.compare(declared(), nil)
  end

  test "reports a lookalike container as out of band" do
    lookalike = actual() |> put_in([:labels], %{})

    assert [%{cause: "out_of_band"}] =
             Comparator.compare(declared(), lookalike, expected_hash: "hash")
  end

  test "reports a changed compose hash as a stale deployment" do
    assert [%{cause: "stale_deployment", field: "config_hash"}] =
             Comparator.compare(declared(), actual(), expected_hash: "new-hash")
  end

  test "reports docker update memory changes as in-place mutations" do
    changed = actual(%{"HostConfig" => %{"Memory" => 1_073_741_824}})

    assert [%{cause: "in_place_mutation", field: "memory", category: "resource"}] =
             Comparator.compare(declared(), changed, expected_hash: "hash")
  end

  test "reports immutable changes as unexplained" do
    changed = actual(%{"HostConfig" => %{"Privileged" => true}})

    assert [%{cause: "unexplained", field: "privileged", severity: "high"}] =
             Comparator.compare(declared(), changed, expected_hash: "hash")
  end

  test "adds image drift without replacing other findings" do
    findings =
      Comparator.compare(declared(), actual(),
        expected_hash: "hash",
        declared_image_id: "sha256:new"
      )

    assert [%{cause: "image_drift", field: "image"}] = findings
  end

  test "ignores undeclared environment variables and cosmetic defaults" do
    assert [] = Comparator.compare(declared(), actual(), expected_hash: "hash")
  end

  test "reports unmanaged containers attached to a project network" do
    container = %{
      "Id" => "lookalike",
      "Labels" => %{},
      "NetworkSettings" => %{"Networks" => %{"demo_default" => %{}}}
    }

    assert [%{cause: "unmanaged_container", severity: "high"}] =
             Comparator.unmanaged([container], ["demo_default"])
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value),
        do: deep_merge(left_value, right_value),
        else: right_value
    end)
  end
end
