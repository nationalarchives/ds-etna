# ETNA

https://tna.dblclk.dev

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
npx playwright test
npx playwright test --ui
npx playwright test --update-snapshots
TEST_DOMAIN=https://develop.tna.dblclk.dev npx playwright test
```
