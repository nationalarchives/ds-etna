FROM pjcdawkins/platformsh-cli:latest

ARG DATABASE_HOST
ARG DATABASE_PORT
ARG DATABASE_NAME
ARG DATABASE_USER
ARG PGPASSWORD
ARG PLATFORM_PROJECT_ID
ARG PLATFORMSH_CLI_TOKEN

WORKDIR /app

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y openssh-server git libpopt0 rsync postgresql

RUN mkdir db_backups && \
    NOW=$(date +%s) && \
    platform db:dump -e main -p "$PLATFORM_PROJECT_ID" -f "/app/db_backups/$NOW.psql"

CMD pg_dump -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER" --clean && \
    psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER" < "/app/db_backups/$NOW.psql"
