# Conformance suite

The Lumencast conformance suite is a **language-agnostic** test harness that verifies an implementation correctly speaks LSDP/1 and processes LSML 1.0.

## Why this exists

For Lumencast to be a real standard, multiple implementations (TypeScript, Go, Rust, Python, Elixir, ...) must produce **byte-identical** wire frames and apply LSML scenes identically. Without a conformance suite, drift is inevitable. With it, drift is automatically detected.

## Structure

```
conformance/
├── manifest.json                    # Indexed catalogue of fixtures + scenarios
├── README.md                        # this file
└── v1/                              # LSDP/1 + LSML 1.0
    ├── SCENARIO-FORMAT.md           # Authoritative scenario YAML format
    ├── fixtures/                    # Byte-level golden frames
    │   ├── client/                  # Client → server frames
    │   │   ├── subscribe-minimal.json
    │   │   ├── subscribe-with-scene-and-session.json
    │   │   ├── input-single-patch.json
    │   │   ├── input-multiple-patches.json
    │   │   └── ping.json
    │   └── server/                  # Server → client frames
    │       ├── snapshot-empty.json
    │       ├── snapshot-with-state.json
    │       ├── delta-single-patch.json
    │       ├── delta-multiple-patches.json
    │       ├── scene-changed.json
    │       ├── error-auth-denied.json
    │       ├── error-write-forbidden.json
    │       ├── error-unknown-path.json
    │       ├── error-rate-limit.json
    │       └── pong.json
    └── scenarios/                   # End-to-end protocol behaviours
        ├── subscribe-snapshot-delta.yaml
        ├── delta-multiple-patches-atomic.yaml
        ├── delta-replay-tolerated.yaml
        ├── seq-gap-triggers-reconnect.yaml
        ├── seq-resets-on-scene-changed.yaml
        ├── auth-denied-closes.yaml
        ├── viewer-cannot-input.yaml
        ├── operator-input-echoes-as-delta.yaml
        ├── unknown-path-rejected.yaml
        ├── invalid-value-rejected.yaml
        ├── test-session-namespace.yaml
        ├── bundle-incompatible-rejects.yaml
        ├── token-rotation-no-flicker.yaml
        ├── ping-pong-roundtrip.yaml
        ├── envelope-rejects-future-major.yaml
        └── unknown-frame-type-ignored.yaml
```

The `manifest.json` indexes everything with tags (`required` / `recommended` / `extended`) and target type (`server` / `runtime` / `any`).

The `SCENARIO-FORMAT.md` is the **normative format spec** — the YAML structure of a scenario, the step kinds, the matching semantics, the placeholder vocabulary. Every conformance runner implements this format identically.

## Fixture format

A **byte-level fixture** is a JSON file representing a single LSDP frame as it would appear on the wire (after WebSocket text-frame decoding). The conformance runner :
- Encodes the fixture with the implementation under test
- Decodes back
- Compares to the original (round-trip)

Fixtures live in `v1/fixtures/<direction>/<frame-type-or-variant>.json` where direction is `client` (client → server) or `server` (server → client).

Example `v1/fixtures/server/snapshot-with-state.json` :

```json
{
  "v": 1,
  "type": "snapshot",
  "seq": 1,
  "scene_id": "test-scene",
  "scene_version": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  "state": {
    "title": "Hello",
    "count": 0
  }
}
```

## Scenario format

A **scenario** is a YAML file describing a sequence of frames exchanged between client and server, plus expected outcomes. The full normative format lives in [`v1/SCENARIO-FORMAT.md`](v1/SCENARIO-FORMAT.md). Brief example :

```yaml
name: reconnect-after-gap
description: Runtime detects sequence gap and reconnects, fresh snapshot follows.

steps:
  - server-sends:
      type: snapshot
      seq: 1
      scene_id: s1
      scene_version: sha256:abc
      state: { x: 1 }

  - server-sends:
      type: delta
      seq: 2
      patches: [{ path: x, value: 2 }]

  - server-sends:
      type: delta
      seq: 5            # gap! seq 3 and 4 missing
      patches: [{ path: x, value: 5 }]

  - expect-client:
      action: close-with-reason
      reason: VERSION_GAP

  - expect-client:
      action: reconnect

  - server-sends:
      type: snapshot
      seq: 1            # fresh subscription
      scene_id: s1
      scene_version: sha256:abc
      state: { x: 5 }

  - expect-runtime-state:
      x: 5
```

## How to run conformance

The canonical runner is the `lumencast` CLI (Go-based, single binary), which lives in the `lumencast-go` repo. Until it's published :

```sh
# Future
lumencast conformance --target server   --url wss://my-server.example.com
lumencast conformance --target client   --client-cmd "node ./build/runtime.js"
lumencast conformance --target sdk      --sdk-cmd "go run ./cmd/sdk-test"
```

The runner :
1. Loads the fixtures and scenarios
2. For each scenario, drives the implementation through the steps
3. Checks expected outcomes against actual behavior
4. Reports pass/fail with diff on mismatches
5. Exits 0 if all scenarios pass, 1 otherwise

## Coverage requirements

To claim "LSDP/1 conformance", an implementation MUST pass every scenario tagged `required` in `manifest.json` for every target it claims to implement (`server`, `runtime`, or `any`).

The tag system maps directly to the RFC 2119 keywords used in the spec :

| Tag | RFC 2119 mapping | Conformance impact | Scenarios |
|---|---|---|---|
| `required` | MUST | Failure means the implementation is NOT LSDP/1 conformant ; the "Lumencast" name MUST NOT be used without qualification (see [LSDP-1.md §15.3](../spec/LSDP-1.md#153-naming-policy)). | Core protocol behaviour, error codes (with required `path` field for path-scoped codes per [§3.4.1](../spec/LSDP-1.md#341-per-code-extra-fields)), sequencing rules including the pre-snapshot `seq=1` clause from [§5.1](../spec/LSDP-1.md#51-error-frames-before-any-snapshot), role enforcement, atomic input rejection. |
| `recommended` | SHOULD | Failure does not break conformance but the implementation SHOULD document the deviation. | Reconnect timing, rate-limit handling with `retry_after_ms` advice, recovery patterns, edge cases. |
| `extended` | MAY | Failure is acceptable and discouraged but not blocking. | Performance budgets, large-state behaviour, optional metadata. |

This partition is normative — it mirrors [LSDP-1.md §15.1](../spec/LSDP-1.md#151-conformance-profile-partition). When in doubt, the spec is authoritative.

Conformance is **target-scoped**. A scenario with `target: server` tests server behaviour ; a scenario with `target: runtime` tests runtime/client behaviour ; a scenario with `target: any` tests both. An implementation claims conformance only for the targets it actually implements — a server-only SDK is not required to pass `target: runtime` scenarios (they're auto-skipped).

### Test control plane

Server implementations claiming conformance MUST expose the [test control plane](../interop/CONTROL.md). Runtime implementations claiming conformance MUST be drivable through it. The control plane is normative ; an implementation that does not honour it cannot be conformance-tested and therefore MUST NOT claim LSDP/1 conformance.

## Adding new scenarios

To add a scenario :

1. Create the `.yaml` file under `v1/scenarios/`
2. Add it to `manifest.json` with appropriate tag
3. Verify the scenario fails before the implementation supports it (test the test)
4. Verify the scenario passes after implementation
5. Open a PR with a clear description

## Authority

This suite is the source of truth. If an implementation passes the suite but disagrees with the spec text, the spec text is the bug. If an implementation disagrees with the suite, the implementation is the bug. If the suite disagrees with the spec, file an issue immediately — divergence is a release-blocker.

## License

Apache 2.0, same as the rest of `lumencast-protocol`.
