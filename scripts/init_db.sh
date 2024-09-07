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
