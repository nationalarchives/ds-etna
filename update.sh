#!/bin/bash

set -Eeuo pipefail

HEALTHCHECK_TIMEOUT=${HEALTHCHECK_TIMEOUT:-300}
NGINX_DRAIN_TIMEOUT=${NGINX_DRAIN_TIMEOUT:-300}

fail() {
  echo "ERROR: $*" >&2
  return 1
}

nginx_workers() {
  docker exec nginx sh -c '
    for process in /proc/[0-9]*/cmdline; do
      [ -r "$process" ] || continue
      command=$(tr "\000" " " < "$process")
      case "$command" in
        "nginx: worker process"*)
          pid=${process#/proc/}
          echo "${pid%/cmdline}"
          ;;
      esac
    done
  '
}

reload_nginx() {
  local old_workers workers pid deadline draining
  docker exec nginx /usr/sbin/nginx -t -c /etc/nginx/etna-conf/nginx.conf
  old_workers=$(nginx_workers)
  [[ -n "$old_workers" ]] || fail "No nginx workers found"
  echo "Reloading nginx"
  docker exec nginx /usr/sbin/nginx -c /etc/nginx/etna-conf/nginx.conf -s reload

  # Reload is asynchronous; old workers retain their upstreams until requests finish.
  deadline=$((SECONDS + NGINX_DRAIN_TIMEOUT))
  while ((SECONDS < deadline)); do
    workers=$(nginx_workers)
    draining=false
    while IFS= read -r pid; do
      if [[ $'\n'"$workers"$'\n' == *$'\n'"$pid"$'\n'* ]]; then
        draining=true
      fi
    done <<< "$old_workers"
    if [[ "$draining" == false && -n "$workers" ]]; then
      return 0
    fi
    sleep 1
  done
  fail "nginx did not finish draining within ${NGINX_DRAIN_TIMEOUT}s; original containers have not been stopped"
}

wait_for_health() {
  local container_id=$1 state deadline
  deadline=$((SECONDS + HEALTHCHECK_TIMEOUT))
  while ((SECONDS < deadline)); do
    state=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")
    case "$state" in
      "running healthy") return 0 ;;
      "running starting") sleep 1 ;;
      *)
        fail "Container $container_id is $state; original container has not been stopped"
        return 1
        ;;
    esac
  done
  fail "Container $container_id did not become healthy within ${HEALTHCHECK_TIMEOUT}s; original container has not been stopped"
}

single_container() {
  local service_name=$1 containers
  containers=$(docker compose ps --all --quiet "$service_name")
  if [[ -z "$containers" || "$containers" == *$'\n'* ]]; then
    fail "Expected exactly one container for $service_name; resolve any previous incomplete deployment first"
    return 1
  fi
  printf '%s\n' "$containers"
}

zero_downtime_deploy() {
  local service_name=$1 old_container_id new_container_id="" containers container_id
  local nginx_network new_container_ip
  echo "------------------------------------------"
  echo "Redeploying $service_name"
  old_container_id=$(single_container "$service_name")
  echo "Old container ID: $old_container_id ($service_name)"

  docker compose up -d --no-deps --scale "$service_name=2" --no-recreate "$service_name"

  containers=$(docker compose ps --all --quiet "$service_name")
  while IFS= read -r container_id; do
    if [[ "$container_id" != "$old_container_id" ]]; then
      [[ -z "$new_container_id" ]] || fail "Multiple replacements found for $service_name"
      new_container_id=$container_id
    fi
  done <<< "$containers"
  [[ -n "$new_container_id" ]] || fail "No replacement found for $service_name"
  echo "New container ID: $new_container_id ($service_name)"
  wait_for_health "$new_container_id"

  nginx_network=$(docker inspect -f '{{range $name, $network := .NetworkSettings.Networks}}{{println $name}}{{end}}' nginx)
  nginx_network=${nginx_network%$'\n'}
  [[ -n "$nginx_network" && "$nginx_network" != *$'\n'* ]] ||
    fail "Expected nginx to be attached to exactly one network"
  new_container_ip=$(docker inspect -f "{{with index .NetworkSettings.Networks \"$nginx_network\"}}{{.IPAddress}}{{end}}" "$new_container_id")
  [[ -n "$new_container_ip" ]] || fail "Replacement is not on nginx's network"
  echo "New container IP: $new_container_ip ($service_name)"

  # Pin the primary to the healthy replacement, rather than both DNS addresses.
  printf 'server %s:8080;\n' "$new_container_ip" |
    docker exec -i nginx sh -c 'cat > "/etc/nginx/etna-upstreams/$1.conf.tmp" && mv "/etc/nginx/etna-upstreams/$1.conf.tmp" "/etc/nginx/etna-upstreams/$1.conf"' sh "$service_name"
  reload_nginx

  # take the old container offline
  echo "Stopping and removing $old_container_id ($service_name)"
  docker stop "$old_container_id"
  docker rm "$old_container_id"

  echo "$service_name updated"
}

main() {
  local service_name container_id nginx_command
  [[ "$HEALTHCHECK_TIMEOUT" =~ ^[1-9][0-9]*$ && "$NGINX_DRAIN_TIMEOUT" =~ ^[1-9][0-9]*$ ]] ||
    fail "Deployment timeouts must be positive integers"
  git pull --ff-only
  docker compose pull
  docker compose up -d --no-recreate

  nginx_command=$(docker inspect -f '{{json .Config.Cmd}}' nginx)
  [[ "$nginx_command" == *"/etc/nginx/etna-conf/nginx.conf"* ]] ||
    fail "nginx needs the new configuration mount; recreate nginx once during a maintenance window before deploying"
  for service_name in service-status chat; do
    container_id=$(single_container "$service_name")
    wait_for_health "$container_id"
  done
  docker exec -i nginx sh < conf/10-etna-upstreams.sh
  reload_nginx
  zero_downtime_deploy service-status
  zero_downtime_deploy chat
  df -h -k /dev/sda1
  # Prune Docker if disk usage is above 80%.
  if df -hP -k /dev/sda1 | awk '{if ($5+0>=80) exit 1}'; then echo "Space OK"; else docker system prune --force --all --volumes; fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap 'echo "ERROR: Deployment failed at line $LINENO; inspect the containers before retrying" >&2' ERR
  main
fi
