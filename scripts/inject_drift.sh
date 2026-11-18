#!/usr/bin/env bash
set -euo pipefail

# This script is intentionally limited to the fixture project named below.
# Usage: scripts/inject_drift.sh <1|2|3|4|5> <apply|revert>

project="kairos_m0"
compose_file="test/fixtures/compose/docker-compose.yml"
scenario="${1:?scenario required}"
action="${2:?apply or revert required}"

if [[ ! -f "$compose_file" || "$project" != "kairos_m0" ]]; then
  echo "Refusing to operate outside the Kairos fixture project." >&2
  exit 1
fi

compose() { docker compose --project-name "$project" --file "$compose_file" "$@"; }
reset() { compose up --detach --force-recreate --remove-orphans; }

case "$scenario:$action" in
  1:apply)
    cp "$compose_file" "${compose_file}.drift-backup"
    sed -i 's/mem_limit: 128m/mem_limit: 192m/' "$compose_file"
    ;;
  1:revert)
    mv "${compose_file}.drift-backup" "$compose_file"
    ;;
  2:apply)
    docker run --detach --rm --name "${project}-web-99" --network "${project}_default" nginx:alpine >/dev/null
    ;;
  2:revert)
    docker rm --force "${project}-web-99" >/dev/null 2>&1 || true
    ;;
  3:apply)
    docker update --memory 256m "${project}-web-1" >/dev/null
    ;;
  3:revert)
    reset
    ;;
  4:apply)
    docker pull nginx:alpine >/dev/null
    ;;
  4:revert)
    echo "Image-tag drift requires restoring the tag in the fixture registry context." >&2
    ;;
  5:apply)
    compose stop worker
    ;;
  5:revert)
    compose start worker
    ;;
  *)
    echo "Unsupported scenario/action. Use 1..5 and apply|revert." >&2
    exit 2
    ;;
esac
