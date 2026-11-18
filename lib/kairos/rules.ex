defmodule Kairos.Rules do
  @moduledoc "The sole source of impact and mutability decisions."

  @rules [
    %{
      field: "read_only",
      category: "security",
      severity: "medium",
      mutable?: false,
      rationale: "A writable root filesystem expands the container's attack surface."
    },
    %{
      field: "cap_add",
      category: "security",
      severity: "high",
      mutable?: false,
      rationale: "Added Linux capabilities grant privileges outside the declared workload."
    },
    %{
      field: "cap_drop",
      category: "security",
      severity: "high",
      mutable?: false,
      rationale: "Dropped capabilities no longer match the declared security boundary."
    },
    %{
      field: "privileged",
      category: "security",
      severity: "high",
      mutable?: false,
      rationale: "Privileged containers substantially weaken host isolation."
    },
    %{
      field: "user",
      category: "security",
      severity: "medium",
      mutable?: false,
      rationale: "The process user differs from the declared execution identity."
    },
    %{
      field: "security_opt",
      category: "security",
      severity: "high",
      mutable?: false,
      rationale: "Security options differ from the declared container hardening."
    },
    %{
      field: "environment",
      category: "security",
      severity: "medium",
      mutable?: false,
      rationale: "A declared environment value differs; values are fingerprinted."
    },
    %{
      field: "volumes",
      category: "security",
      severity: "high",
      mutable?: false,
      rationale: "Mount configuration differs from the declared filesystem boundary."
    },
    %{
      field: "ports",
      category: "network",
      severity: "high",
      mutable?: false,
      rationale: "Published ports expose network reachability beyond the declaration."
    },
    %{
      field: "networks",
      category: "network",
      severity: "medium",
      mutable?: false,
      rationale: "Network attachment differs from the declared topology."
    },
    %{
      field: "dns",
      category: "network",
      severity: "medium",
      mutable?: false,
      rationale: "DNS configuration differs from the declared resolver set."
    },
    %{
      field: "restart",
      category: "lifecycle",
      severity: "medium",
      mutable?: true,
      rationale: "Restart behavior was changed on the deployed container."
    },
    %{
      field: "memory",
      category: "resource",
      severity: "medium",
      mutable?: true,
      rationale: "The memory limit was changed in place."
    },
    %{
      field: "cpus",
      category: "resource",
      severity: "medium",
      mutable?: true,
      rationale: "The CPU limit was changed in place."
    },
    %{
      field: "pids_limit",
      category: "resource",
      severity: "medium",
      mutable?: true,
      rationale: "The PID limit was changed in place."
    }
  ]

  @spec all() :: [map()]
  def all, do: @rules

  @spec fetch(String.t()) :: map()
  def fetch(field),
    do:
      Enum.find(@rules, &(&1.field == field)) ||
        %{
          field: field,
          category: "image",
          severity: "medium",
          mutable?: false,
          rationale: "The declared image differs from the deployed image."
        }
end
