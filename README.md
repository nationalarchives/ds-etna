# ds-etna

## Docker compose

```sh
SECRET_KEY=$(python -c 'import secrets; print(secrets.token_hex())')
POSTGRES_PASSWORD=$(python -c 'import secrets; print(secrets.token_hex())')

docker-compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --dry-run -d tna.dblclk.dev

docker-compose up -d

docker-compose run --rm certbot renew
```