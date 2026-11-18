# Kairos usage guide

Kairos detects Docker Compose drift by comparing the current Compose declaration,
the Compose labels stamped on a deployed container, and current `docker inspect`
data. It is read-only: Kairos never creates, updates, starts, stops, or removes
workload containers.

## Requirements

- Elixir 1.18+ and Erlang/OTP 27+
- Docker Engine and Docker Compose v2 for live scans
- A non-root account able to read `/var/run/docker.sock`, normally through the
  `docker` group or through a read-only socket mount

Verify access first:

```bash
docker version
docker compose version
id -nG
```

Never expose `/var/run/docker.sock` or an unauthenticated Docker TCP endpoint.
Docker-group membership is effectively privileged host access.

## Installation and state

From the repository root:

```bash
mix deps.get
mix compile --warnings-as-errors
```

Kairos stores SQLite state in `./data` by default. Choose an agent-local path
with `KAIROS_DATA`:

```bash
export KAIROS_DATA=/var/lib/kairos
```

The first run creates `$KAIROS_DATA/fp.key`, a random owner-only fingerprint key.
Do not copy it between unrelated environments: that would make secret
fingerprints linkable across environments.

## Scan a Compose project

```bash
mix kairos.scan --project demo --file docker-compose.yml
mix kairos.scan --project demo --file docker-compose.yml --json
```

`--project` must match the Compose project name and `--file` is the declaration
to evaluate. A scan prints findings, or a JSON array with `--json`, and persists
a normalized snapshot plus hash-chain entry. `[]` means no drift in supported
fields.

## What is compared

For every declared service, Kairos compares:

- Declared state: `docker compose config --format json`
- Deployed record: Compose project, service, and config-hash labels
- Actual state: `docker inspect`

Supported fields: read-only root filesystem, capabilities, privileged mode,
user, security options, declared environment keys, mounts, ports, networks,
DNS, memory, CPU, PID limit, restart policy, and image ID.

Values are normalized to avoid cosmetic findings: ordering, Docker defaults,
empty host IP versus `0.0.0.0`, `CAP_` prefixes, Compose network prefixes,
restart retry `0`, and Docker memory units. Environment values are
HMAC-fingerprinted before comparison, output, or storage.

Possible causes are `missing`, `out_of_band`, `stale_deployment`,
`in_place_mutation`, `unexplained`, `image_drift`, and `unmanaged_container`.
Kairos does not assign severity or priority; people and their organization make
that decision after reviewing the evidence.

## History, events, and investigation

```bash
mix kairos.history
mix kairos.verify
mix kairos.events --since 300
mix kairos.explain <finding_id>
mix kairos.plan --project demo --file docker-compose.yml
```

History reports `new`, `recurring`, and `resolved` findings. `verify` checks the
snapshot SHA-256 chain. `events` records lifecycle actions (`create`, `start`,
`die`, `update`, `destroy`, `rename`) while removing environment/secret-like
attributes. `plan` is read-only; it never applies a Docker change.

Docker events identify an action and container, not the responsible actor.
Correlate their timestamps/container IDs with auditd, sudo, SSH, CI, or
authenticated API-proxy logs.

## Tests

The regular tests do not build or start containers:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test test/kairos/image_ab_test.exs
mix test test/kairos/collector_plug_test.exs
```

The image A/B test verifies both a matching deployed/resolved image ID (clean)
and a changed ID (`image_drift`).

### Local Docker integration test

This builds the isolated fixture image, starts two `kairos_ci` containers, scans
them, verifies a temporary hash chain, then removes the fixture:

```bash
KAIROS_FIXTURE_PORT=18081 docker compose --project-name kairos_ci --file test/fixtures/compose/docker-compose.yml up --detach --build
KAIROS_FIXTURE_PORT=18081 KAIROS_DATA=/tmp/kairos-ci-artifacts mix kairos.scan --project kairos_ci --file test/fixtures/compose/docker-compose.yml --json
KAIROS_DATA=/tmp/kairos-ci-artifacts mix kairos.verify
docker compose --project-name kairos_ci --file test/fixtures/compose/docker-compose.yml down --volumes --remove-orphans
```

Use another port if `18081` is unavailable. The CI workflow has separate unit,
Docker-integration, and multi-host-contract jobs; it uploads scan results as
artifacts.

## Multi-host deployment

Run one Kairos agent per Docker host. Keep each Docker socket local. Send only
normalized snapshots/findings to a central collector at `POST /v1/snapshots`
with a valid `X-Kairos-Agent-Id`.

Deploy the collector behind HTTPS with mutual TLS from a private CA, on a
private network or behind an mTLS proxy. Do not route Docker API traffic through
the collector or use it to issue remote Docker commands.

This repository supplies the validated collector contract
(`Kairos.Collector.Plug`) and tests. The HTTPS listener, certificate issuance,
host identity mapping, and agent uploader must be deployed with your own
network and identity policy; those secrets are intentionally absent here.

Kubernetes and other orchestrators require their own collectors and
normalization contracts.

## Troubleshooting

- Docker permission errors: verify account membership and any workspace socket
  policy.
- Fixture port conflict: set `KAIROS_FIXTURE_PORT` to a free port.
- `stale_deployment`: review the Compose change and redeploy through the normal
  deployment process if intended.
- `unexplained`: investigate before redeploying; it can indicate tampering or a
  normalization gap.
- Hash-chain failure: preserve the database and fingerprint key for
  investigation rather than overwriting them.
