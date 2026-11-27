#!/bin/sh
# The roles of ADR 0007 (M2-36), created once when the postgres volume is initialized, as the
# superuser of the image (POSTGRES_USER, which only this container knows):
#   sermon_owner    owns the database and applies the migrations (the one-shot migrate service);
#                   no superuser, no BYPASSRLS, so FORCE ROW LEVEL SECURITY binds it as well
#   sermon_definer  owns the SECURITY DEFINER functions; no login (the migrations use it)
#   sermon_app      the login of sermon-server; owns nothing
#   sermon_backup   the login of "sermon-server backup" (V1-05, ADR 0042): reads everything
#                   (pg_read_all_data) in every organization (BYPASSRLS), writes nothing
# The TimescaleDB extension itself is created by the image's own init script; schema objects come
# from the server's migrations.
set -eu

owner_password="$(cat /run/secrets/postgres_owner_password)"
app_password="$(cat /run/secrets/postgres_app_password)"
backup_password="$(cat /run/secrets/postgres_backup_password)"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v owner_password="$owner_password" -v app_password="$app_password" -v backup_password="$backup_password" \
  -v db="$POSTGRES_DB" <<'SQL'
-- :'owner_password', :'app_password' and :'backup_password' are psql variables (quoted by psql), not secrets.
CREATE ROLE sermon_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
  PASSWORD :'owner_password'; -- betterleaks:allow
CREATE ROLE sermon_definer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT sermon_definer TO sermon_owner;
CREATE ROLE sermon_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
  PASSWORD :'app_password'; -- betterleaks:allow
CREATE ROLE sermon_backup LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION BYPASSRLS
  IN ROLE pg_read_all_data PASSWORD :'backup_password'; -- betterleaks:allow
-- The owner of the database owns its schema public (pg_database_owner).
ALTER DATABASE :"db" OWNER TO sermon_owner;
SQL
