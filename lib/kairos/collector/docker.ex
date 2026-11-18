defmodule Kairos.Collector.Docker do
  @moduledoc "Minimal read-only Docker Engine client over the local Unix socket."

  @socket "/var/run/docker.sock"

  @spec inspect_container(String.t()) :: {:ok, map()} | {:error, term()}
  def inspect_container(id), do: get_json("/containers/#{URI.encode(id)}/json")

  @spec inspect_image(String.t()) :: {:ok, map()} | {:error, term()}
  def inspect_image(reference), do: get_json("/images/#{URI.encode(reference)}/json")

  @spec containers_for_project(String.t()) :: {:ok, [map()]} | {:error, term()}
  def containers_for_project(project) do
    filters = JSON.encode!(%{"label" => ["com.docker.compose.project=#{project}"]})
    get_json("/containers/json?all=1&filters=#{URI.encode_www_form(filters)}")
  end

  @spec all_containers() :: {:ok, [map()]} | {:error, term()}
  def all_containers, do: get_json("/containers/json?all=1")

  @spec events(integer()) :: {:ok, [map()]} | {:error, term()}
  def events(since) do
    with {:ok, body} <-
           request("GET", "/events?since=#{since}&until=#{System.system_time(:second)}") do
      events =
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, event} -> [event]
            _ -> []
          end
        end)

      {:ok, events}
    end
  end

  defp get_json(path) do
    with {:ok, body} <- request("GET", path),
         {:ok, decoded} <- JSON.decode(body) do
      {:ok, decoded}
    end
  end

  defp request(method, path) do
    # OTP's TCP transport supports Unix-domain sockets directly when the address
    # is `{:local, path}`. Mint then provides the regular HTTP/1 framing.
    opts = [hostname: "localhost", protocols: [:http1]]

    with {:ok, conn} <- Mint.HTTP.connect(:http, {:local, @socket}, 0, opts),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, method, path, [], nil) do
      receive_response(conn, ref, [])
    end
  end

  defp receive_response(conn, ref, chunks) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            case Enum.reduce(responses, {:continue, chunks}, &handle_response(&1, ref, &2)) do
              {:done, body} ->
                Mint.HTTP.close(conn)
                {:ok, IO.iodata_to_binary(Enum.reverse(body))}

              {:continue, next_chunks} ->
                receive_response(conn, ref, next_chunks)
            end

          {:error, _conn, reason, _responses} ->
            {:error, reason}

          :unknown ->
            receive_response(conn, ref, chunks)
        end
    after
      5_000 -> {:error, :docker_timeout}
    end
  end

  defp handle_response({:data, ref, data}, ref, {:continue, chunks}),
    do: {:continue, [data | chunks]}

  defp handle_response({:done, ref}, ref, {:continue, chunks}), do: {:done, chunks}
  defp handle_response(_response, _ref, state), do: state
end
