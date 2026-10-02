# Local continuation gate

`scripts/ci/continuation-spike.sh` evaluates one private fixture contract on the
same host as a successful recovery run. A recovered save file and a normal
emulator exit do not establish that a game resumed the expected state.

## Current result

The configured Mac has passed the parent-owned network-denial probe and the
restored-target recovery journey. Its existing private emulator adapter has not
qualified deterministic input replay and a repeatable visible resumed-state
oracle. The actual continuation result is therefore `qualification /
blocked-capability` (exit 77). No current-run in-game continuation pass is claimed.

The known fixture and disposable-account defaults are in
[TEST-FIXTURES.md](TEST-FIXTURES.md). Reuse them; this result does not call for a
new ROM, personal login, or repeated signing setup.

## Inputs and execution

The configured machine's ignored `.local/run-continuation.py` reuses local
configuration and the latest successful recovery receipt. The repository entry
point accepts these process environment inputs:

| Variable | Purpose |
|---|---|
| `PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM` | Exactly `macos-seatbelt-v1` or `linux-bwrap-v1`; each is available only on its matching host with the fixed tools. |
| `PLAYSTEAD_CONTINUATION_CONTRACT` | Canonical, owned, mode-600 metadata JSON. |
| `PLAYSTEAD_RECOVERY_E2E_RECEIPT` | Canonical, owned, mode-600 successful same-host recovery receipt. |
| `PLAYSTEAD_CONTINUATION_ADAPTER` | Canonical local executable controlled by the operator; no group/world write. |
| `PLAYSTEAD_CONTINUATION_FIXTURE` | Existing private regular file, resolved only after qualification. |

The coordinator can join this gate to a fresh recovery run with
`PLAYSTEAD_CONTINUATION_RUN=1`. In that mode the continuation outcome and exit
status are the final result. A blocked child cannot be reported as overall
success.

The parent validates metadata and the receipt, demonstrates that a reachable
local listener is unreachable inside its fixed containment, and invokes the
adapter with exactly one action: `qualify`, `initial-run`, or `continue`.
Every action repeats the parent probe, strips the child environment to a fixed
PATH, denies network access, and limits writes to a newly owned private working
directory. Fixture-bearing actions have no standalone runner CLI.

The adapter owns its adjacent private fixture mapping, emulator configuration,
input trace and oracle. It receives no private paths or payload in its command
arguments or environment. Qualification must leave the working directory empty.
Only then does the parent create an empty `persistent-save` directory and permit
the two lifecycle actions.

## Contract and evidence

Exact schemas and allowed fields are defined in `continuation_protocol.py` and
covered by `tests/continuation-process-double-test.py`. Unknown/duplicate fields,
invalid identities, oversized results, missing capabilities, stale children,
timeouts and unsafe files are refused. Contract, fixture and child identities
use opaque UUID4 values.

A pass requires qualified capabilities, an initially empty save directory,
a populated save directory after the initial run, safe exit, distinct fresh
child identity, completion of Continue, and at least two agreeing visible-state
oracle runs. The trusted local adapter attests lifecycle and oracle facts; the
parent independently checks containment, bounded process completion and save
directory state. On macOS the process cleanup checks the child's process group;
the adapter must not detach emulator children into another session. Linux also
uses a private PID namespace. This is not a sandbox for arbitrary hostile
operator-supplied code, nor a claim that either host mechanism is universally
available.

Raw output stays in bounded process memory, and temporary roots are removed.
Only a newly constructed receipt reaches the shared evidence sanitizer:
`schema`, opaque `run_id`, fixed `stage`, and `outcome`. Exit 0 means a qualified
oracle pass, 77 means capability/preflight refusal, and 1 means a failure after
fixture access was permitted. Sanitizer rejection produces no public receipt.

## Verification

Run `scripts/ci/tests/continuation-spike-test.sh` for schema, ordering, process,
environment, lifecycle, isolation-invocation and coordinator propagation checks.
These use process doubles and do not qualify a real emulator or oracle. Real
qualification must independently replay the established fixture and demonstrate
the resumed-state oracle under the selected containment before changing the
current blocked result.
