defmodule Kairos.RecordedFixtureTest do
  use ExUnit.Case, async: true

  alias Kairos.{Comparator, Normalizer}

  test "the sanitized live baseline has no drift" do
    fixture =
      "test/fixtures/recorded/baseline.json"
      |> File.read!()
      |> JSON.decode!()

    declared = Normalizer.declared(fixture["service"], fixture["compose"], project: "kairos_m0")
    actual = Normalizer.actual(fixture["service"], fixture["inspect"])

    assert [] =
             Comparator.compare(declared, actual,
               expected_hash: "a10582a62304807d45b48df06ab84d35b48f034d78cd7396f12969c3fd5a1a36"
             )
  end
end
