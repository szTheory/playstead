# SAVE-P1 Probe Report

**Probe:** SAVE-P1 · **Run ID:** `B03366BE-3A67-4E71-9D57-17BD9EA41D80`
**Recorded at:** 2026-09-03T23:38:55Z
**Host:** macOS 26.6.2, Mac17,9, filesystem `apfs`, page size 16384 bytes, 32768-byte synthetic artifact

This probe converts four inferences from the Phase 4 discussion research
(`discussion-research/A-capture-trigger-and-loss-window.md`, D-02) into
measurements taken on this Mac, using a self-contained synthetic `MAP_SHARED`
writer rather than a real mGBA process. See `mgba_observed` below for what
that boundary means.

## Inode stability

`st_dev`/`st_ino` were recorded before the first mutation and after each of
five `mmap` + mutate + `msync` rounds. All six observations returned the
identical pair (`st_dev=16777229`, `st_ino=228353922`).

**Result: `stable: true`.** On this host, an in-place `MAP_SHARED` writer
does not rotate the file's inode identity — the mmap-in-place architectural
reading that Area A's research treated as inference is now a measurement.

## mtime fidelity

Across the same five rounds, every observed content-digest change was
accompanied by an `st_mtimespec` advance (0 counter-examples in either
direction: `content_changed_without_mtime_advance_count: 0`,
`mtime_advanced_without_content_change_count: 0`).

**Result: mtime tracked content changes faithfully on this host.** This does
not change the design — D-01 and D-03 already forbid mtime-based heuristics
regardless of fidelity — but it forecloses the temptation permanently, with a
number instead of a guess.

## Event delivery (FSEvents / vnode)

An `FSEventStreamCreate` stream on the temp directory and a
`DispatchSource.makeFileSystemObjectSource` vnode watch on the open
descriptor were both registered before five `mmap`/`msync` mutation rounds
with **no `write(2)` call at all**. Both mechanisms fired: 1 FSEvents batch
and 6 vnode events across the run, with every round's mutation observed
within roughly 22–24 ms.

**Result: an event accelerant is available on this host for an mmap/msync
writer on APFS.** This directly measures the claim documented for
inotify/fanotify but previously unmeasured for FSEvents. It does not change
the shipped design: D-01's session-scoped 1 Hz poll remains the trigger
regardless of this result, because polling is also the settle mechanism and
the ground truth, not merely a notification source.

## Post-death writeback

A child process mapped the artifact `MAP_SHARED`, mutated it without calling
`msync`, and was then killed with `SIGKILL`. The parent polled the file's
digest for up to 10 seconds afterward.

**Result: `digest_changed_after_process_death: false`.** No additional
writeback was observed in the poll window on this host and this run. This
does not change D-05 — the post-exit settle pass stays unconditional
regardless of this result, because a `false` here reflects one run's timing
on one host, not a guarantee that dirty pages never land late elsewhere.

## `mgba_observed`

**`mgba_observed: false`.** No `--mgba-artifact` path was supplied for this
run, so every measurement above comes from the probe's own synthetic
`MAP_SHARED` writer, never a real mGBA process. The real-emulator
confirmation — that a real mGBA process exhibits the same behavior against
real commercial game bytes — is carried by **CP7-SAVE-C** (plan 04-12) and
must never be inferred from this report.

## Effect on the design

None. D-01's session-scoped 1 Hz read-and-hash poll and D-03's
three-identical-reads quiescence rule are **unchanged** by these
measurements. D-02 states plainly that no outcome changes D-01: this probe
converts four inferences into four recorded measurements, it does not decide
the capture trigger. The trigger was already correct because it is the
instrument that produced the phase's 24-second flush-cadence constraint in
the first place; this report only removes the word "probably" from the
supporting claims.
