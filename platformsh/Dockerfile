FROM pjcdawkins/platformsh-cli:latest

ARG DATABASE_HOST
ARG DATABASE_PORT
ARG DATABASE_NAME
ARG DATABASE_USER
ARG PGPASSWORD
ARG PLATFORM_PROJECT_ID
ARG PLATFORM_ENV
ARG PLATFORMSH_CLI_TOKEN

WORKDIR /app

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y openssh-server git libpopt0 rsync postgresql

RUN mkdir db_backups
CMD NOW=$(date +%s) && \
    platform db:dump -e "$PLATFORM_ENV" -p "$PLATFORM_PROJECT_ID" -f "./db_backups/$NOW.psql" && \
    sed -i "s@beta.nationalarchives.gov.uk@tna.dblclk.dev@g" "./db_backups/$NOW.psql" && \
    sed -i "s@develop-sr3snxi-rasrzs7pi6sd4.uk-1.platformsh.site@tna.dblclk.dev@g" "./db_backups/$NOW.psql" && \
    pg_dump -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER" --clean && \
    psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER" < "./db_backups/$NOW.psql" && \
    platform mount:download -e "$PLATFORM_ENV" -p "$PLATFORM_PROJECT_ID" -m media --target=/media --exclude="/images/*" --yes
