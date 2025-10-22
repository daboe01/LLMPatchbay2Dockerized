#!/bin/bash

set -e

cd /usr/src/app

NEED_INIT=false
PGDIR=/var/lib/postgresql/18/main
if [ ! -f "$PGDIR"/PG_VERSION ]; then
  /usr/lib/postgresql/18/bin/initdb --encoding=UTF8 -D $PGDIR
  NEED_INIT=true
fi

chmod 700 /var/lib/postgresql/18/main

/etc/init.d/postgresql start

if [ "$NEED_INIT" = true ]; then
  until pg_isready -U postgres; do echo "Waiting for PostgreSQL..."; sleep 2; done
  psql -U postgres --command "CREATE USER docker WITH SUPERUSER PASSWORD 'docker';"
  createdb -U docker --encoding=UTF8 llm_patchbay
  createdb -U docker --encoding=UTF8 minion
  psql -U docker llm_patchbay < sql_template.sql
fi

# Check if the 'ollama' command exists and is executable
if [ -x "$(command -v ollama)" ]; then
  echo "Ollama detected, starting service in the background..."
  ollama serve &
else
  echo "Ollama not found, skipping."
fi

# Start the main application in the background
echo "Starting LLMPatchbay backend..."
hypnotoad /usr/src/app/backend.pl &
# tail -f /var/log/postgresql/postgresql-18-main.log &
# Start the job processor in the foreground
perl /usr/src/app/backend.pl minion worker
