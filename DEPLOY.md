# Deploy on the Docker Compose server

These steps describe the deployment used for Rodrigo's fork at `/docker/invidious`. They assume the Compose service names are `invidious` and `invidious-db`, the PostgreSQL user/database are `kemal`/`invidious`, and the local image is `invidious-shorts:master`. Adapt those names if the server configuration changes. Keep secrets in the server's existing Compose configuration; do not commit them.

## Update the checkout without losing server configuration

Run commands from `/docker/invidious`. Check local changes first:

```bash
cd /docker/invidious
git status --short
```

Preserve the server's customized `docker-compose.yml` outside the checkout, fetch the fork's `master`, and verify the commit before switching. The example uses the merge commit from the November 2026 deployment; future deployments should expect the current fork tip instead.

```bash
stamp=$(date +%Y%m%d-%H%M%S)
cp -a docker-compose.yml "/docker/docker-compose.yml.server-$stamp"
git fetch https://github.com/rtomagnini/invidious.git master
git log -1 --oneline FETCH_HEAD
git restore docker-compose.yml
git switch --detach FETCH_HEAD
cp -a "/docker/docker-compose.yml.server-$stamp" docker-compose.yml
```

Stop if `git status` shows other tracked changes that must be kept, or if the fetched commit is not the intended fork revision. Keep the backup of the server Compose file outside the repository. The detached checkout is intentional for deploying the exact fetched commit.

## Build and verify the image

Build from the updated checkout and verify the embedded commit before touching the database:

```bash
docker compose build --no-cache invidious
docker compose run --rm invidious /invidious/invidious --version
```

Confirm the version contains the commit you fetched. For the November 2026 merge it was `2026.11.05-6443addf`. A version such as `2026.11.04-79761abc` indicates a different checkout/image; do not continue until the source and build context are corrected.

## Back up the database and apply schema changes

Create a restricted database backup before deployment. Ensure the destination has enough free space and retain the backup until the updated instance is verified:

```bash
stamp=$(date +%Y%m%d-%H%M%S)
umask 077
docker compose exec -T invidious-db pg_dump -U kemal -d invidious \
  > "/docker/invidious-$stamp.sql"
```

Stop only the application service, leaving PostgreSQL running, then run the migrations from the same image you verified:

```bash
docker compose stop invidious
docker compose run --rm invidious /invidious/invidious --migrate
```

The full binary path is required because the image entrypoint uses Tini; passing only `--migrate` makes Tini try to execute an executable named `--migrate`.

`No migrations to run` does not prove the schema has every expected column. Check the Shorts columns:

```bash
docker compose exec invidious-db psql -U kemal -d invidious -c \
  "SELECT table_name, column_name FROM information_schema.columns
   WHERE table_schema = 'public'
     AND (table_name, column_name) IN
       (('channel_videos', 'is_short'), ('channels', 'shorts_continuation'))
   ORDER BY table_name, column_name;"
```

If either column is missing, apply the same idempotent schema change as the Shorts migration. This also refreshes subscription feeds so they can be reclassified:

```bash
docker compose exec -T invidious-db psql -v ON_ERROR_STOP=1 -U kemal -d invidious <<'SQL'
ALTER TABLE public.channel_videos ADD COLUMN IF NOT EXISTS is_short boolean;
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS shorts_continuation text;
UPDATE public.users SET feed_needs_update = true;
SQL
```

The SQL can be rerun safely if the columns already exist. Do not drop or recreate the migration table or application tables to resolve a schema mismatch.

## Start and check Invidious

```bash
docker compose up -d invidious
docker compose ps
docker compose logs --tail=100 invidious
```

Open the server's configured Invidious URL and verify `/feed/subscriptions` and `/api/v1/stats`. Keep the database backup and Compose backup until these checks pass. If startup fails, inspect the application logs and restore the previous image/configuration using the deployment procedure for your server.
