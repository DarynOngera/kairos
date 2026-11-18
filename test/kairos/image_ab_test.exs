defmodule Kairos.ImageABTest do
  use ExUnit.Case, async: true

  alias Kairos.{Comparator, Normalizer}

  setup do
    images = "test/fixtures/recorded/image_ab.json" |> File.read!() |> JSON.decode!()

    declared = Normalizer.declared("web", %{})

    inspect = %{
      "Id" => "container-id",
      "Config" => %{
        "Labels" => %{
          "com.docker.compose.project" => "demo",
          "com.docker.compose.service" => "web",
          "com.docker.compose.config-hash" => "hash"
        }
      },
      "HostConfig" => %{},
      "NetworkSettings" => %{"Networks" => %{}}
    }

    %{images: images, declared: declared, inspect: inspect}
  end

  test "A: resolved declared tag matches the deployed image", ctx do
    actual =
      Normalizer.actual(
        "web",
        Map.put(ctx.inspect, "Image", ctx.images["aligned_actual_image_id"])
      )

    assert [] =
             Comparator.compare(ctx.declared, actual,
               expected_hash: "hash",
               declared_image_id: ctx.images["declared_image_id"]
             )
  end

  test "B: resolved declared tag differs from the deployed image", ctx do
    actual =
      Normalizer.actual(
        "web",
        Map.put(ctx.inspect, "Image", ctx.images["drifted_actual_image_id"])
      )

    assert [
             %{
               cause: "image_drift",
               field: "image",
               declared: "sha256:declared-image",
               actual: "sha256:replacement-image"
             }
           ] =
             Comparator.compare(ctx.declared, actual,
               expected_hash: "hash",
               declared_image_id: ctx.images["declared_image_id"]
             )
  end
end
