#!/bin/bash

reload_nginx() {
  echo "Reloading nginx"
  docker exec nginx /usr/sbin/nginx -s reload
}

zero_downtime_deploy() {
  service_name=$1
  echo "------------------------------------------"
  echo "Redeploying $service_name"
  old_container_id=$(docker ps -f name=$service_name -q | tail -n1)
  echo "Old container ID: $old_container_id ($service_name)"

  # bring a new container online, running new code
  # (nginx continues routing to the old container only)
  docker compose up -d --no-deps --scale $service_name=2 --no-recreate $service_name

  # wait for new container to be available
  new_container_id=$(docker ps -f name=$service_name -q | head -n1)
  new_container_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $new_container_id)
  echo "New container ID: $new_container_id ($service_name)"
  echo "New container IP: $new_container_ip ($service_name)"
  curl --silent --include --retry-connrefused --retry 60 --retry-delay 1 --fail http://$new_container_ip:8080/healthcheck/live/ || exit 1

  # start routing requests to the new container (as well as the old)
  reload_nginx

  # take the old container offline
  echo "Stopping and removing $old_container_id ($service_name)"
  docker stop $old_container_id
  docker rm $old_container_id

  docker compose up -d --no-deps --scale $service_name=1 --no-recreate $service_name

  # stop routing requests to the old container
  reload_nginx

  echo "$service_name updated"
}

git pull
docker compose up -d
docker compose pull
# zero_downtime_deploy cms
zero_downtime_deploy search_api
zero_downtime_deploy search
zero_downtime_deploy frontend
zero_downtime_deploy frontend-develop
df -h -k /dev/sda1
# Prune Docker if disk usage is above 80%
if df -hP -k /dev/sda1 | awk '{if ($5+0>=80) exit 1}'; then echo "Space OK"; else docker system prune --force --all --volumes; fi
