defmodule Kairos.StoreTest do
  use ExUnit.Case, async: false

  alias Kairos.Store

  @dir "/tmp/kairos-store-test"

  test "chains snapshots and tracks finding lifecycle" do
    File.rm_rf!(@dir)

    finding = %{
      service: "web",
      cause: "in_place_mutation",
      field: "memory",
      category: "resource",
      severity: "medium",
      declared: 1,
      actual: 2
    }

    assert {:ok, _} = Store.record("demo", %{"web" => %{}}, %{"web" => %{}}, [finding], @dir)
    assert {:ok, [%{"status" => "new"}]} = Store.history(@dir)
    assert {:ok, _} = Store.record("demo", %{"web" => %{}}, %{"web" => %{}}, [finding], @dir)
    assert {:ok, [%{"status" => "recurring"}]} = Store.history(@dir)
    assert {:ok, _} = Store.record("demo", %{"web" => %{}}, %{"web" => %{}}, [], @dir)
    assert {:ok, [%{"status" => "resolved"}]} = Store.history(@dir)
    assert :ok = Store.verify(@dir)
  end
end
