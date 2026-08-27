# Upgrading Playstead

## 1. Back up first

Before any upgrade, back up both the database and the blob volume:

```bash
docker compose exec db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup-$(date +%Y%m%d).sql
docker run --rm -v playstead-server_playstead_blobs:/blobs -v "$PWD":/backup alpine \
  tar czf /backup/blobs-backup-$(date +%Y%m%d).tar.gz -C /blobs .
```

Remember: a copy on the same disk is not a backup. Copy both files to
a different disk, machine, or off-site location before proceeding — if
this machine's disk fails, a same-disk copy fails with it.

## 2. Bump the pinned image tag

Every release ships a new `docker-compose.yml` with a new pinned `app`
image tag (and, when relevant, updated `db`/`caddy` tags). Pull the new
compose file for the release you're upgrading to.

## 3. Pull and restart

```bash
docker compose pull
docker compose up -d
```

Ecto migrations run automatically at boot (`Playstead.Release.migrate/0`),
failing loudly with a non-zero exit and the failing migration's name
and error rather than entering a silent crash loop. A boot-time gate
also refuses to start if the database's schema predates the minimum
version this release can safely upgrade from, naming the intermediate
release you need to run first.

## 4. Check health

```bash
curl -k https://localhost/healthz
```

Expect `200`. If the `app` container is unhealthy or restarting, check
`docker compose logs app` for the migration or boot-gate failure
message before doing anything else.

## Migration discipline (binding on every future phase)

All migrations in this project are **backward-compatible and
forward-only**. A release never ships destructive DDL (dropping a
column, dropping a table, renaming in place) in the same release that
stops using it. The old shape stays readable by the previous release
for at least one full release cycle, so a rollback (see below) never
finds a schema it can't run against.

## Rollback (Phase 1)

At this phase, rollback means **restoring the pre-upgrade backup** you
took in step 1 — there is no automated rollback tooling yet. Restore
the database dump and blob archive to a fresh volume, then run
`docker compose up -d` against the previous release's compose file and
image tag.

Automated upgrade preflight checks and rollback tooling are planned for
Phase 5 (OPER-04) — this manual backup-and-restore procedure is the
complete story for Phase 1.
