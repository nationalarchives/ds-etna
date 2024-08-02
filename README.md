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

```sh
npm install
npx playwright test
npx playwright test --ui
npx playwright test --update-snapshots
TEST_DOMAIN=https://develop.tna.dblclk.dev npx playwright test
```
