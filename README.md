# ETNA

- https://tna.dblclk.dev
- https://develop.tna.dblclk.dev

## Applications

| Resource   | Docker image | Status                                                                                                                                                   |
| ---------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frontend   | [national-archives-website-frontend](https://github.com/nationalarchives/ds-etna-frontend/pkgs/container/national-archives-website-frontend) | ![Build status](https://img.shields.io/github/actions/workflow/status/nationalarchives/ds-etna-frontend/cd.yml?style=flat-square&event=push&branch=main) |
| CMS        | [national-archives-website](https://github.com/nationalarchives/ds-wagtail/pkgs/container/national-archives-website)                         | ![Build status](https://img.shields.io/github/actions/workflow/status/nationalarchives/ds-wagtail/cd.yml?style=flat-square&event=push&branch=develop)    |
| Search API | [national-archives-search-api](https://github.com/nationalarchives/ds-etna-search/pkgs/container/national-archives-search-api)               | ![Build status](https://img.shields.io/github/actions/workflow/status/nationalarchives/ds-etna-search/cd.yml?style=flat-square&event=push&branch=main)   |

## Docker compose

```sh
# Set up env vars
touch .env
echo "SECRET_KEY=$(python -c 'import secrets; print(secrets.token_hex())')" >> .env
echo "POSTGRES_PASSWORD=$(python -c 'import secrets; print(secrets.token_hex())')" >> .env
echo "KONG_CLIENT_KEY=[key]" >> .env
echo "PLATFORMSH_CLI_TOKEN=[token]" >> .env

# Start the services
docker compose up -d

# Test certbot - remove --dry-run if working
docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --dry-run -d tna.dblclk.dev

# Renew cert
docker compose run --rm certbot renew
```

## Updating applications without downtime

Run `bash ./update.sh` from this directory (the deployment workflow uses the
same script). It pulls the images without recreating running containers, then
updates `service-status` and `chat` one at a time:

1. Start a second container, keeping nginx pointed at the original.
2. Wait for Docker's image-defined healthcheck to report `healthy`.
3. Point nginx exclusively at the replacement's IP and gracefully reload.
4. Wait for old nginx workers to finish their in-flight requests before
   stopping and removing the original container.

Both application images must define a Docker healthcheck; a missing healthcheck,
unhealthy/stopped replacement, or failed nginx reload aborts the deployment.
`HEALTHCHECK_TIMEOUT` and `NGINX_DRAIN_TIMEOUT` default to 300 seconds each and
can be overridden with positive integer environment variables. Long-lived chat
connections can delay draining; on timeout both containers are left running.
Inspect the failure and resolve the extra container before retrying; the script
requires exactly one existing container per application.

Before a handoff, a failed replacement can be removed while keeping the
original. After a drain timeout, the replacement is already primary: keep both
running until the old nginx workers finish, then remove the original, not the
replacement.

Application services must remain scalable (no fixed `container_name` or
host-published ports). nginx's entrypoint initialises its upstream files on
startup. Its configuration directory is mounted rather than a single file so
that config files replaced by `git pull` are visible on reload.

**One-time migration:** existing nginx containers need the new directory mount
and startup command. During a maintenance window, run
`docker compose up -d --no-deps --force-recreate nginx`. This briefly interrupts
nginx; subsequent application updates do not recreate it. The update script
refuses to proceed with the old nginx configuration mount.

Do not use a plain `docker compose up` or force-recreate nginx for
routine application updates: those operations bypass the graceful handoff.
Infrastructure changes requiring container recreation need a separate
maintenance window.

### Deployment tests

Run `bash tests/update_test.sh` for the mocked failure-path tests and
`shellcheck -x update.sh conf/10-etna-upstreams.sh tests/update_test.sh` for lint.
`python3 tests/update_integration.py` exercises the real nginx configuration with
continuous HTTPS traffic and held requests. It requires Docker, Compose, Python,
OpenSSL, and locally available `nginx:latest` and `python:3.14-slim-trixie` images.
It creates an isolated Compose project and removes its containers afterwards;
it does not run the deployment script's git, image-pull, or pruning steps.
