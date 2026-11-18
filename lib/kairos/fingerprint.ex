defmodule Kairos.Fingerprint do
  @moduledoc "Produces non-reversible fingerprints for values that must not be displayed."

  @spec value(String.t(), binary()) :: String.t()
  def value(value, key \\ key()) when is_binary(value) do
    :crypto.mac(:hmac, :sha256, key, value) |> Base.encode16(case: :lower)
  end

  @spec key() :: binary()
  def key do
    Application.get_env(:kairos, :fingerprint_key) ||
      System.get_env("KAIROS_FP_KEY") ||
      "kairos-development-key-change-before-persisting"
  end
end
