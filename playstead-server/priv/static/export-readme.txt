These are your games, exported as ordinary files.

Every file under data/ is exactly the bytes Playstead stored for you —
never transformed, recompressed, or padded. manifest-sha256.txt lists
each one with its SHA-256 digest; you can check every file yourself
with the standard "sha256sum -c manifest-sha256.txt" command, or any
BagIt-aware tool, with no Playstead software installed at all.

A copy of this folder on the same disk as your Playstead server is not a backup.
If the disk fails, both copies are lost. Keep a copy somewhere else —
another disk, another machine, or removable media — if you want this
export to survive a hardware failure.
