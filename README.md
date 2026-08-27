# Playstead

Playstead is an open-source, self-hostable personal game-library and continuity system. Its first proof is a polished Mac client connected to a private Phoenix server: import user-supplied game files without changing the originals, browse without mirroring the full library, selectively cache and play offline, preserve compatible persistent saves, and export everything as ordinary verifiable files.

## Workspace

This repository is the Playstead workspace and planning root. The first implementation boundaries are tracked as directories in one repository:

- [`playstead-server/`](playstead-server/) — Phoenix server, versioned HTTPS API, LiveView console, custody, import/export, durable jobs, transfers, saves, and operations.
- [`playstead-mac/`](playstead-mac/) — SwiftUI/AppKit reference client, offline catalogue and cache, controller and emulator adapters, launch preflight, and save continuity.

This is intentionally not a collection of nested Git repositories. A `playstead-protocol` package, independent web client, or supporting libraries may be extracted later only after a stable boundary and more than one consumer prove the need.

## Product priorities

1. Data safety and recoverability
2. Reliable local play and save continuity
3. Clarity, accessibility, and low-administration operation
4. Performance and resource efficiency
5. Integrated delight
6. Feature breadth

The canonical project definition, requirements, and roadmap live in [`.planning/`](.planning/). Start with [`.planning/PROJECT.md`](.planning/PROJECT.md) and [`.planning/ROADMAP.md`](.planning/ROADMAP.md).

## Content posture

Playstead handles private, user-supplied content. It does not distribute, locate, or facilitate acquisition of copyrighted ROMs or proprietary BIOS files. Supported open BIOS replacements may be integrated where licensing permits; user-supplied BIOS files must remain explicit, validated, and portable.
