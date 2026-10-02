# The inbox folder

`inbox/` is where a self-hoster stages files for import. Its contents are
yours; Playstead only ever reads them.

- **Dev default.** `config/runtime.exs` points `:inbox_path` at this directory
  in the `:dev` environment, so a native `mix phx.server` run needs no
  configuration — drop files in and they appear in the import UI.
- **Containerized.** `docker-compose.yml` bind-mounts this same directory
  read-only at `/app/inbox`; `docker-compose.dev.yml` does the same via its
  `.:/app` mount. The `:ro` is load-bearing, not decorative: it makes "your
  source file stays where it is" a kernel guarantee rather than an
  application-code promise (D-01).
- **Override anywhere.** `PLAYSTEAD_INBOX_PATH` takes precedence in every
  environment.

## What the scan reports

`Playstead.Import.Inbox.scan/1` walks the folder on an explicit console action
only — there is no watcher and no polling loop — and reports **every regular
file** it finds, with two deliberate exceptions:

- **Symbolic links are reported, never followed.** The read-only mount protects
  your files from Playstead, not Playstead from your filesystem, so a link
  pointing elsewhere is named rather than traversed.
- **Dot-entries are skipped**, files and directories alike. Finder writes
  `.DS_Store` the moment you open this folder; volumes collect `.Trashes`,
  `.Spotlight-V100` and `.fseventsd`; copying between disks leaves `._`
  AppleDouble files. Reported, each would become an `:unknown` item demanding a
  decision at `/attention` that you never made — and `.DS_Store` returns as soon
  as you open the folder again, so excluding it would never settle it. Nothing
  you deliberately stage is hidden: dot-files do not appear in the file manager
  you would have used to put them there.

That second rule is also why this directory is kept alive in git with a tracked
`.gitkeep` rather than a `README.md`. **The project must not ship content into a
folder it has told you is yours** — a tracked README here is scanned as your
content and reported as an unknown file on every preview, which is exactly the
phantom the rule above exists to prevent.

## Unzip first

Archives are detected by **magic bytes, never by file extension**, and are kept
completely unopened — nothing is listed, no central directory is read, no byte is
decompressed. A `.zip`, `.7z`, `.rar`, gzip, xz or zstd file imports as an opaque
blob and **cannot be launched**. It lands in `/attention` under *Archives kept
unopened*, where your only options are `Retain as custom` or `Exclude`. Extract
it outside Playstead and re-import the bare ROM.
