defmodule Kairos.Store do
  @moduledoc "SQLite persistence for normalized Kairos scan results."

  alias Kairos.Repo

  @schema [
    """
    CREATE TABLE IF NOT EXISTS snapshots (
      id INTEGER PRIMARY KEY, taken_at TEXT NOT NULL, project TEXT NOT NULL,
      declared_json TEXT NOT NULL, actual_json TEXT NOT NULL,
      sha256 TEXT NOT NULL UNIQUE, prev_sha256 TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS findings (
      id INTEGER PRIMARY KEY, snapshot_id INTEGER NOT NULL, fingerprint TEXT NOT NULL,
      service TEXT NOT NULL, cause TEXT NOT NULL, field TEXT NOT NULL,
      category TEXT NOT NULL, declared TEXT, actual TEXT,
      FOREIGN KEY(snapshot_id) REFERENCES snapshots(id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS finding_state (
      fingerprint TEXT PRIMARY KEY, first_seen TEXT NOT NULL, last_seen TEXT NOT NULL,
      status TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY, time INTEGER NOT NULL, container_id TEXT NOT NULL,
      action TEXT NOT NULL, attributes_json TEXT NOT NULL
    )
    """
  ]

  @spec record(String.t(), map(), map(), [map()], String.t() | nil) ::
          {:ok, integer()} | {:error, term()}
  def record(project, declared, actual, findings, data_dir \\ nil) do
    with :ok <- ensure_ready(data_dir),
         {:ok, snapshot_id} <- insert_snapshot(project, declared, actual),
         :ok <- insert_findings(snapshot_id, findings) do
      {:ok, snapshot_id}
    end
  end

  @spec history(String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def history(data_dir \\ nil) do
    with :ok <- ensure_ready(data_dir),
         {:ok, result} <-
           Ecto.Adapters.SQL.query(
             Repo,
             "SELECT f.id, f.service, f.cause, f.field, f.category, s.first_seen, s.last_seen, s.status FROM findings f JOIN finding_state s ON f.fingerprint = s.fingerprint GROUP BY f.fingerprint ORDER BY s.last_seen DESC",
             []
           ) do
      {:ok, rows(result)}
    end
  end

  @spec verify(String.t() | nil) :: :ok | {:error, term()}
  def verify(data_dir \\ nil) do
    with :ok <- ensure_ready(data_dir),
         {:ok, result} <-
           Ecto.Adapters.SQL.query(
             Repo,
             "SELECT project, declared_json, actual_json, sha256, prev_sha256 FROM snapshots ORDER BY id",
             []
           ) do
      verify_rows(rows(result), nil)
    end
  end

  @spec fingerprint_key(String.t() | nil) :: {:ok, binary()} | {:error, term()}
  def fingerprint_key(data_dir \\ nil) do
    dir = data_dir(data_dir)
    path = Path.join(dir, "fp.key")

    with :ok <- File.mkdir_p(dir) do
      case File.read(path) do
        {:ok, key} ->
          {:ok, key}

        {:error, :enoent} ->
          key = :crypto.strong_rand_bytes(32)

          with :ok <- File.write(path, key, [:binary]),
               :ok <- File.chmod(path, 0o600),
               do: {:ok, key}

        error ->
          error
      end
    end
  end

  @spec record_events([map()], String.t() | nil) :: :ok | {:error, term()}
  def record_events(events, data_dir \\ nil) do
    with :ok <- ensure_ready(data_dir) do
      Enum.each(events, fn event ->
        attrs =
          event |> Map.get("Actor", %{}) |> Map.get("Attributes", %{}) |> sanitize_attributes()

        Ecto.Adapters.SQL.query!(
          Repo,
          "INSERT INTO events (time, container_id, action, attributes_json) VALUES (?, ?, ?, ?)",
          [
            Map.get(event, "time", 0),
            Map.get(event, "id", ""),
            Map.get(event, "Action", ""),
            canonical_json(attrs)
          ]
        )
      end)

      :ok
    end
  rescue
    error -> {:error, error}
  end

  @spec finding(integer(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def finding(id, data_dir \\ nil) do
    with :ok <- ensure_ready(data_dir),
         {:ok, %{rows: [row]}} <-
           Ecto.Adapters.SQL.query(
             Repo,
             "SELECT id, service, cause, field, category, declared, actual FROM findings WHERE id = ?",
             [id]
           ) do
      {:ok,
       row
       |> List.to_tuple()
       |> then(fn tuple ->
         %{
           id: elem(tuple, 0),
           service: elem(tuple, 1),
           cause: elem(tuple, 2),
           field: elem(tuple, 3),
           category: elem(tuple, 4),
           declared: elem(tuple, 5),
           actual: elem(tuple, 6)
         }
       end)}
    else
      {:ok, _} -> {:error, :finding_not_found}
      error -> error
    end
  end

  defp ensure_ready(data_dir) do
    dir = data_dir(data_dir)
    db = Path.join(dir, "kairos.db")

    with :ok <- File.mkdir_p(dir),
         {:ok, _key} <- fingerprint_key(dir),
         :ok <- start_repo(db) do
      Enum.each(@schema, &Ecto.Adapters.SQL.query!(Repo, &1, []))
      remove_legacy_severity_column()
      :ok
    end
  end

  defp remove_legacy_severity_column do
    columns = Ecto.Adapters.SQL.query!(Repo, "PRAGMA table_info(findings)", []).rows

    if Enum.any?(columns, fn row -> Enum.at(row, 1) == "severity" end) do
      Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE findings DROP COLUMN severity", [])
    end
  end

  defp start_repo(db) do
    case Process.whereis(Repo) do
      nil ->
        case Repo.start_link(database: db, pool_size: 1, log: false) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp insert_snapshot(project, declared, actual) do
    declared_json = canonical_json(declared)
    actual_json = canonical_json(actual)

    previous =
      Ecto.Adapters.SQL.query!(Repo, "SELECT sha256 FROM snapshots ORDER BY id DESC LIMIT 1", [])

    prev_sha =
      case previous.rows do
        [[sha]] -> sha
        [] -> nil
      end

    body = %{project: project, declared: declared, actual: actual, prev_sha256: prev_sha}
    sha = :crypto.hash(:sha256, canonical_json(body)) |> Base.encode16(case: :lower)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    case Ecto.Adapters.SQL.query(
           Repo,
           "INSERT INTO snapshots (taken_at, project, declared_json, actual_json, sha256, prev_sha256) VALUES (?, ?, ?, ?, ?, ?) RETURNING id",
           [now, project, declared_json, actual_json, sha, prev_sha]
         ) do
      {:ok, %{rows: [[id]]}} -> {:ok, id}
      error -> error
    end
  end

  defp insert_findings(snapshot_id, findings) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    known = MapSet.new(Enum.map(findings, &finding_fingerprint/1))

    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE finding_state SET status = 'resolved' WHERE status != 'resolved'",
      []
    )

    Enum.reduce_while(findings, :ok, fn finding, :ok ->
      fingerprint = finding_fingerprint(finding)

      state =
        Ecto.Adapters.SQL.query!(
          Repo,
          "SELECT fingerprint FROM finding_state WHERE fingerprint = ?",
          [fingerprint]
        )

      status = if state.rows == [], do: "new", else: "recurring"

      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO findings (snapshot_id, fingerprint, service, cause, field, category, declared, actual) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
          snapshot_id,
          fingerprint,
          finding.service,
          finding.cause,
          finding.field,
          finding.category,
          canonical_json(finding.declared),
          canonical_json(finding.actual)
        ]
      )

      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO finding_state (fingerprint, first_seen, last_seen, status) VALUES (?, ?, ?, ?) ON CONFLICT(fingerprint) DO UPDATE SET last_seen = excluded.last_seen, status = excluded.status",
        [fingerprint, now, now, status]
      )

      {:cont, :ok}
    end)

    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE finding_state SET status = 'resolved' WHERE fingerprint NOT IN (#{placeholders(MapSet.size(known))})",
      MapSet.to_list(known)
    )

    :ok
  rescue
    error -> {:error, error}
  end

  defp placeholders(0), do: "NULL"
  defp placeholders(count), do: Enum.map_join(1..count, ",", fn _ -> "?" end)

  defp finding_fingerprint(finding) do
    finding
    |> Map.take([:service, :cause, :field, :category, :declared, :actual])
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp data_dir(nil), do: System.get_env("KAIROS_DATA") || "data"
  defp data_dir(path), do: path
  defp rows(%{columns: columns, rows: rows}), do: Enum.map(rows, &Map.new(Enum.zip(columns, &1)))

  defp sanitize_attributes(attrs),
    do:
      Map.reject(attrs, fn {key, _value} ->
        key
        |> String.downcase()
        |> then(
          &(String.contains?(&1, "env") or String.contains?(&1, "secret") or
              String.contains?(&1, "token") or String.contains?(&1, "password"))
        )
      end)

  defp verify_rows([], _prev), do: :ok

  defp verify_rows([row | rest], prev) do
    with {:ok, declared} <- JSON.decode(row["declared_json"]),
         {:ok, actual} <- JSON.decode(row["actual_json"]) do
      body = %{project: row["project"], declared: declared, actual: actual, prev_sha256: prev}
      sha = :crypto.hash(:sha256, canonical_json(body)) |> Base.encode16(case: :lower)

      if sha == row["sha256"] and row["prev_sha256"] == prev,
        do: verify_rows(rest, sha),
        else: {:error, :hash_chain_invalid}
    end
  end

  defp canonical_json(value) when is_map(value),
    do:
      "{" <>
        (value
         |> Enum.map(fn {key, item} -> {to_string(key), item} end)
         |> Enum.sort_by(&elem(&1, 0))
         |> Enum.map_join(",", fn {key, item} ->
           JSON.encode!(key) <> ":" <> canonical_json(item)
         end)) <> "}"

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: JSON.encode!(value)
end
