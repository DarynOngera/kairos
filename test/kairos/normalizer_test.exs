defmodule Kairos.NormalizerTest do
  use ExUnit.Case, async: true

  alias Kairos.Normalizer

  @key "test-key"

  test "normalizes cosmetic Docker equivalents and fingerprints secrets" do
    declared =
      Normalizer.declared(
        "web",
        %{
          "cap_add" => ["NET_ADMIN"],
          "ports" => [%{"target" => 80, "published" => 8080}],
          "environment" => %{"SECRET" => "not-printed"}
        },
        fingerprint_key: @key
      )

    actual =
      Normalizer.actual(
        "web",
        %{
          "Config" => %{"Env" => ["SECRET=not-printed"], "Labels" => %{}},
          "HostConfig" => %{
            "CapAdd" => ["CAP_NET_ADMIN"],
            "PortBindings" => %{"80/tcp" => [%{"HostIp" => "", "HostPort" => "8080"}]}
          }
        },
        fingerprint_key: @key
      )

    assert declared.fields["cap_add"] == actual.fields["cap_add"]
    assert declared.fields["ports"] == actual.fields["ports"]
    assert declared.fields["environment"] == actual.fields["environment"]
    refute inspect(actual) =~ "not-printed"
  end
end
