defmodule Kairos.Collector.Compose do
  @moduledoc "Read-only wrapper around `docker compose config`."

  @spec config(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def config(project, file) do
    with {:ok, output} <-
           docker([
             "compose",
             "--project-name",
             project,
             "--file",
             file,
             "config",
             "--format",
             "json"
           ]),
         {:ok, config} <- JSON.decode(output) do
      {:ok, config}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      _ -> {:error, "Docker Compose returned invalid JSON"}
    end
  end

  @spec hash(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def hash(project, file, service) do
    case docker([
           "compose",
           "--project-name",
           project,
           "--file",
           file,
           "config",
           "--hash",
           service
         ]) do
      {:ok, output} -> {:ok, output |> String.trim() |> String.split() |> List.last()}
      error -> error
    end
  end

  defp docker(args) do
    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, String.trim(output)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
