# Local continuation gate

`scripts/ci/continuation-spike.sh` evaluates one private fixture contract on the
same host as a successful recovery run. A recovered save file and a normal
emulator exit do not establish that a game resumed the expected state.

## Current result

The current local run passed after the parent verified the loopback network-denial
probe. Two independent fresh-root runs used the checksum-verified mGBA 0.10.5
Libretro core with the registered AerevenAdvance ROM and save. Each captured the
settled Continue menu, sent a deterministic six-frame A press at frames 300–305,
and required a different stable in-game frame. A fresh process then loaded the
emitted save and reproduced that exact in-game framebuffer. The captured private
frame shows the world map; the four-field receipt is `oracle/passed` (run ID
`049db954-1ba3-4968-880f-e11d9426261e`). Synthetic-only qualification passed
separately as `qualification/qualified-only`.

This result qualifies only this mGBA 0.10.5 core and the AerevenAdvance fixture.
It does not qualify the Qt application frontend, Playstead's shipped emulator
adapter, arbitrary mGBA content, or full PORT-04/QUAL-02 completion. The
remaining phase gates stay open.

The fixture is the already registered owner-supplied homebrew ROM and persistent
save. This offline core proof did not use a test account, pairing, personal
login, or local Playstead app.

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
directory. On macOS the profile denies process execution by default and allows
only the validated adapter, required system Python runtime chain, and validated
adjacent C frontends. Fixture-bearing actions have no standalone runner CLI.

The adapter owns its adjacent private fixture mapping, emulator configuration,
input trace and oracle. It receives no private paths or payload in its command
arguments or environment. Qualification must leave the working directory empty.
Only then does the parent create an empty `persistent-save` directory and permit
the two lifecycle actions.

The synthetic core capability step can be run with
`scripts/ci/continuation-spike.sh --qualify-only`. It uses the same validated
contract, successful recovery receipt, containment and network-denial probe,
then runs only `qualify`. The parent returns
`qualification/qualified-only` and exits successfully when the adapter proves
the synthetic capability contract. This is intentionally a different receipt
from `oracle/passed`; it does not assert that a private fixture resumed. The
parent returns from this mode before reading or resolving
`PLAYSTEAD_CONTINUATION_FIXTURE`. The adapter remains trusted local code, so
this guarantee covers parent orchestration and its scrubbed child environment;
the test adapter must use only generated synthetic content.

## Contract and evidence

Exact schemas and allowed fields are defined in `continuation_protocol.py` and
covered by `tests/continuation-process-double-test.py`. Unknown/duplicate fields,
invalid identities, oversized results, missing capabilities, stale children,
timeouts and unsafe files are refused. Contract, fixture and child identities
use opaque UUID4 values.

A pass requires qualified capabilities, an initially empty save directory,
a populated save directory after the initial run, safe exit, distinct fresh
child identity, completion of Continue, and at least two agreeing visible-state
oracle observations. The fixture frontend captures the settled menu at frame
299, presses A for frames 300–305, and rejects a result that remains on the
menu. It requires the resulting game frame to repeat and the new process to
reproduce the same RGB565 frame after loading the emitted SRAM file. The trusted
local adapter attests lifecycle and oracle facts; the parent independently
checks containment, bounded process completion and save-directory state. On
macOS the process cleanup checks the child's process group; the adapter must not
detach emulator children into another session. Linux also uses a private PID
namespace. This is not a sandbox for arbitrary hostile operator-supplied code,
nor a claim that either host mechanism is universally available.

Raw output stays in bounded process memory, and temporary roots are removed.
Only a newly constructed receipt reaches the shared evidence sanitizer:
`schema`, opaque `run_id`, fixed `stage`, and `outcome`. Exit 0 means either the
synthetic-only `qualification/qualified-only` result or a fixture-backed
`oracle/passed` result, depending on the requested mode. Exit 77 means
capability/preflight refusal, and 1 means a failure after fixture access was
permitted. Sanitizer rejection produces no public receipt.

## Verification

Run `scripts/ci/tests/continuation-spike-test.sh` for schema, ordering, process,
environment, lifecycle, isolation-invocation and coordinator propagation checks.
These use process doubles and do not qualify a real emulator or oracle. The
current sanitized local receipt records the separate real-core result; its scope
remains limited to mGBA 0.10.5 and this registered fixture.
