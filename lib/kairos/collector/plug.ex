defmodule Kairos.Collector.Plug do
  @moduledoc "Accepts normalized findings from mutually authenticated Kairos agents."
  use Plug.Router

  plug(Plug.Parsers, parsers: [:json], json_decoder: JSON)
  plug(:match)
  plug(:dispatch)

  post "/v1/snapshots" do
    with [agent_id] <- get_req_header(conn, "x-kairos-agent-id"),
         true <- valid_agent_id?(agent_id),
         %{"declared" => declared, "actual" => actual, "findings" => findings} <-
           conn.body_params,
         {:ok, id} <- Kairos.Store.record("agent:" <> agent_id, declared, actual, findings) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(202, JSON.encode!(%{snapshot_id: id}))
    else
      _ -> send_resp(conn, 400, "invalid normalized snapshot")
    end
  end

  match(_, do: send_resp(conn, 404, "not found"))

  defp valid_agent_id?(id), do: String.match?(id, ~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}\z/)
end
