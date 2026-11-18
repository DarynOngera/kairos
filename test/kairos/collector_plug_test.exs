defmodule Kairos.Collector.PlugTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  test "rejects uploads without a host identity" do
    conn =
      conn(
        :post,
        "/v1/snapshots",
        JSON.encode!(%{"declared" => %{}, "actual" => %{}, "findings" => []})
      )
      |> put_req_header("content-type", "application/json")

    assert %{status: 400} = Kairos.Collector.Plug.call(conn, [])
  end
end
