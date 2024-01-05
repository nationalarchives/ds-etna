# ds-etna

## Docker compose

```sh
touch .env
echo "SECRET_KEY=$(python -c 'import secrets; print(secrets.token_hex())')" >> .env
echo "POSTGRES_PASSWORD=$(python -c 'import secrets; print(secrets.token_hex())')" >> .env
echo "KONG_CLIENT_KEY=[key]" >> .env

docker-compose up -d

docker-compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --dry-run -d tna.dblclk.dev

docker-compose run --rm certbot renew
```