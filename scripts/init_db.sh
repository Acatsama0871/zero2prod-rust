#!/usr/bin/env bash
set -x
set -eo pipefail

# check if the custom user has been set, if not default to 'postgres'
DB_USER=${POSTGRES_USER:=postgres}
DB_PASSWORD=${POSTGRES_PASSWORD:=password}

# check if the custom database name has been set, if not default to 'newsletter'
DB_NAME=${POSTGRES_DB:=newsletter}
# check if the custom port has been set, if not default to '5432'
DB_PORT=${POSTGRES_PORT:=5432}
# check if the custom host has been set, if not default to 'localhost'
DB_HOST=${POSTGRES_HOST:=localhost}

docker run \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${DB_PASSWORD} \
    -e POSTGRES_DB=${DB_NAME} \
    -p ${DB_PORT}:5432 \
    -d postgres \
    postgres -N 1000

# keep pinging the postgres until it is ready to accept commands
export PGPASSWORD=${DB_PASSWORD}
until  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q'; do
    >&2 echo "Postgres is still unavailable - sleeping"
    sleep 1
done

DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}
export DATABASE_URL
sqlx database create
sqlx migrate run

>&2 echo "Postgres is up and running on ${DB_PORT}..."
