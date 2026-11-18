# Kairos

Kairos detects Docker Compose configuration drift across multiple hosts. Each
agent scans its local Docker host; agents may send only normalized findings to a
central collector. Its name refers to the opportune moment for action, rather
than sequential time (*Chronos*).

## Setup

Use Elixir 1.18+ and Docker Compose v2. Install dependencies with `mix deps.get`.
Run as a non-root user allowed to read `/var/run/docker.sock` (normally via the
`docker` group), or with a read-only socket mount.

## Scan

```
mix kairos.scan --project demo --file docker-compose.yml
mix kairos.scan --project demo --file docker-compose.yml --json
```

Kairos compares the declared Compose configuration, Compose deployment labels,
and current container inspection. Secret environment values are fingerprinted,
never printed. The collector only makes read-only Docker API requests.

## Limitations

Each individual agent supports Docker Compose on its local host. Kubernetes and
other orchestrators require separate collectors. Kairos does not remediate
drift automatically. Docker events may show what happened but cannot identify
who caused a change without external audit-log correlation.

See `USAGE.md` for commands, safe multi-host deployment, remediation planning,
and audit-log correlation guidance.
