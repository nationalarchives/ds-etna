#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if [[ $# == 0 ]]; then
  scratch=$(mktemp -d)
  trap 'rm -f "$scratch/events" "$scratch/scaled" "$scratch/health" "$scratch/workers"; rmdir "$scratch"' EXIT
  export TEST_STATE=$scratch
  for scenario in healthy healthy-old-first unhealthy missing-health stopped health-timeout inspect-failure scale-failure multiple-originals missing-replacement config-failure reload-failure drain-timeout; do
    rm -f "$scratch/events" "$scratch/scaled" "$scratch/health" "$scratch/workers"
    if output=$(bash "$0" "$scenario" 2>&1); then
      [[ "$scenario" == healthy* ]] || { echo "Unexpected success: $scenario"; exit 1; }
      expected=$'scale\nstarting\nhealthy\nswitch\ntest\nreload\ndrained\nstop old\nrm old'
      [[ "$(cat "$scratch/events")" == "$expected" ]] || {
        echo "Incorrect deployment order: $scenario"
        cat "$scratch/events"
        exit 1
      }
    else
      [[ "$scenario" != healthy* ]] || { echo "$output"; exit 1; }
      [[ "$output" == *"ERROR:"* ]] || { echo "Missing error: $scenario"; exit 1; }
      if [[ -f "$scratch/events" ]] && grep -Eq '^(stop|rm) ' "$scratch/events"; then
        echo "Original container removed after failure: $scenario"
        exit 1
      fi
    fi
    echo "PASS: $scenario"
  done
  exit 0
fi

scenario=$1
# shellcheck source=update.sh
source "$root/update.sh"
export HEALTHCHECK_TIMEOUT=3
export NGINX_DRAIN_TIMEOUT=3

event() { echo "$*" >> "$TEST_STATE/events"; }

sleep() {
  SECONDS=$((SECONDS + 1))
}

docker() {
  case "$1 $2" in
    "compose ps")
      if [[ "$scenario" == multiple-originals ]]; then
        printf 'old\nother\n'
      elif [[ ! -f "$TEST_STATE/scaled" || "$scenario" == missing-replacement ]]; then
        echo old
      elif [[ "$scenario" == healthy-old-first ]]; then
        printf 'old\nnew\n'
      else
        printf 'new\nold\n'
      fi
      ;;
    "compose up")
      [[ "$*" == "compose up -d --no-deps --scale chat=2 --no-recreate chat" ]]
      event scale
      [[ "$scenario" != scale-failure ]] || { fail "Mock scaling failure"; return 1; }
      touch "$TEST_STATE/scaled"
      ;;
    "inspect -f")
      if [[ "$3" == *".State.Status"* ]]; then
        [[ "$4" == new ]]
        case "$scenario" in
          unhealthy) echo "running unhealthy" ;;
          missing-health) echo "running none" ;;
          stopped) echo "exited healthy" ;;
          inspect-failure) fail "Mock inspect failure"; return 1 ;;
          health-timeout) echo "running starting" ;;
          *)
            if [[ -f "$TEST_STATE/health" ]]; then
              event healthy
              echo "running healthy"
            else
              event starting
              touch "$TEST_STATE/health"
              echo "running starting"
            fi
            ;;
        esac
      elif [[ "$4" == nginx ]]; then
        echo test-network
      else
        echo 172.20.0.3
      fi
      ;;
    "exec -i")
      [[ "$(cat)" == "server 172.20.0.3:8080;" ]]
      event switch
      ;;
    "exec nginx")
      if [[ "$*" == *" -t -c "* ]]; then
        event test
        [[ "$scenario" != config-failure ]] || { fail "Mock invalid nginx config"; return 1; }
      elif [[ "$*" == *" -s reload" ]]; then
        event reload
        [[ "$scenario" != reload-failure ]] || { fail "Mock reload failure"; return 1; }
      else
        fail "Unexpected docker call: $*"
        return 1
      fi
      ;;
    "stop old"|"rm old") event "$*" ;;
    *) fail "Unexpected docker call: $*"; return 1 ;;
  esac
}

nginx_workers() {
  if [[ ! -f "$TEST_STATE/workers" ]]; then
    touch "$TEST_STATE/workers"
    echo 100
  elif [[ "$scenario" == drain-timeout ]]; then
    echo 100
  elif [[ ! -s "$TEST_STATE/workers" ]]; then
    echo waiting > "$TEST_STATE/workers"
    printf '100\n200\n'
  else
    event drained
    echo 200
  fi
}

zero_downtime_deploy chat
