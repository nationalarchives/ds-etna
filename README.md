# ds-etna

## Docker compose

```sh
SECRET_KEY=$(python -c 'import secrets; print(secrets.token_hex())')
openssl genrsa -des3 -out ./ssl/tna.dblclk.dev.key 2048
openssl req -x509 -new -nodes -key ./ssl/tna.dblclk.dev.key -sha256 -days 1825 -out ./ssl/tna.dblclk.dev.pem
docker-compose up -d
```