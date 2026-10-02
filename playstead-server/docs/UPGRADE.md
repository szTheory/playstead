# Controlled upgrades and recovery

Every production upgrade is forward-only. Never use `ecto.rollback` as an
incident-response tool, and never restore the database or blob custody alone.

## Required evidence before an in-place update

Keep the prior release artifact by its immutable `sha256:` image digest. Then
record an independently verified Phase 05 backup receipt, capacity evidence,
and a compatibility certificate saying the previous app can read the target
schema for one release cycle. Run the host preflight before Compose is changed:

```bash
docker compose exec app bin/playstead eval 'Mix.Tasks.Playstead.UpgradePreflight.run(["--fixture"])'
```

`--fixture` is the safe contract check used in CI. A production wrapper must
supply real receipt evidence and retain its returned preflight receipt; it must
not infer safety from a copied file, a started container, or `/healthz` alone.
Only a `ready` receipt authorizes the controlled `docker compose pull` then
`docker compose up -d` update. The receipt binds the prior and target digests,
verified backup receipt ID/time, capacity, schema compatibility, and correlation
ID. Migrations remain expand/contract and forward-only.

## Rollback selection after a failed update

There are exactly two outcomes:

1. **App-only rollback** — select the retained prior digest only when its
   compatibility certificate is present and both database and blob integrity are
   green. Record the selected branch and all evidence.
2. **Clean-room database-and-blob recovery** — for every other case, restore
   the pre-upgrade database and blob custody together into newly isolated
   volumes and run the complete `playstead.restore` proof. Do not point a
   restore command at the live Compose project.

The second branch is intentionally the default when evidence is missing,
incompatible, or unhealthy. It is not a partial rollback and it must complete
the authenticated restore and known-playable evidence chain before it is called
recovered.
