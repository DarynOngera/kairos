defmodule Kairos.MixProject do
  use Mix.Project

  def project do
    [
      app: :kairos,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:mint, "~> 1.6"},
        {:ecto_sql, "~> 3.12"},
        {:ecto_sqlite3, "~> 0.17"},
        {:plug, "~> 1.16"},
        {:bandit, "~> 1.5"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ecto_sql, :ecto_sqlite3],
      mod: {Kairos.Application, []}
    ]
  end
end
