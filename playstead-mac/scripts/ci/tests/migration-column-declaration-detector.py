import re, sys

CREATE_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\((.*?)\n\s*\)\s*;",
    re.S | re.I)
ALTER_RE = re.compile(
    r"ALTER\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s+ADD\s+COLUMN\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.I)

def create_columns(body):
    cols, depth, cur = [], 0, []
    for ch in body:
        if ch == "(": depth += 1
        elif ch == ")": depth -= 1
        if ch == "," and depth == 0:
            cols.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    cols.append("".join(cur))
    names = []
    for c in cols:
        c = c.strip()
        if not c: continue
        first = c.split()[0]
        if first.upper() in ("FOREIGN", "PRIMARY", "UNIQUE", "CHECK", "CONSTRAINT"): continue
        names.append(first.strip('"`[]'))
    return names

def main(path):
    src = open(path, encoding="utf-8").read()
    creates = {}
    for m in CREATE_RE.finditer(src):
        creates.setdefault(m.group(1), set()).update(create_columns(m.group(2)))
    missing = []
    checked = 0
    for m in ALTER_RE.finditer(src):
        table, column = m.group(1), m.group(2)
        if table not in creates:
            missing.append(f"{table}.{column} (no CREATE TABLE block for {table} in this file)")
            continue
        checked += 1
        if column not in creates[table]:
            missing.append(f"{table}.{column}")
    if not checked:
        print("FAIL: found no ALTER ... ADD COLUMN statements to check; detector is not matching the source",
              file=sys.stderr)
        return 1
    if missing:
        print("FAIL: these columns exist ONLY because of a defensive ALTER, with no matching", file=sys.stderr)
        print("  entry in their own CREATE TABLE block. On a fresh database the ALTER is the", file=sys.stderr)
        print("  only thing that creates them, so deleting it as 'redundant' silently drops a", file=sys.stderr)
        print("  column the app reads -- and the `try?` swallows the error. See WINDOWS #90.", file=sys.stderr)
        for entry in sorted(missing):
            print(f"  undeclared={entry}", file=sys.stderr)
        return 1
    print(f"verified {checked} ALTER-added columns are each also declared in their CREATE TABLE block")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: migration-column-declaration-detector.py <Migrations.swift>", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
