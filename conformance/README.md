# Conformance suite

The Lumencast conformance suite is a **language-agnostic** test harness that verifies an implementation correctly speaks LSDP/1 and processes LSML 1.0.

## Why this exists

For Lumencast to be a real standard, multiple implementations (TypeScript, Go, Rust, Python, Elixir, ...) must produce **byte-identical** wire frames and apply LSML scenes identically. Without a conformance suite, drift is inevitable. With it, drift is automatically detected.

## Structure

```
conformance/
├── v1/                              # LSDP/1 + LSML 1.0
│   ├── fixtures/                    # Byte-level golden fixtures
│   │   ├── envelope/
│   │   │   ├── snapshot-basic.json
│   │   │   ├── delta-single-patch.json
│   │   │   └── ...
│   │   └── lsml/
│   │       ├── minimal.json
│   │       ├── all-primitives.json
│   │       └── ...
│   ├── scenarios/                   # End-to-end protocol scenarios
│   │   ├── subscribe-snapshot-delta.yaml
│   │   ├── reconnect-after-gap.yaml
│   │   ├── token-rotation.yaml
│   │   ├── scene-changed-resets-seq.yaml
│   │   ├── viewer-cannot-input.yaml
│   │   ├── operator-input-validates.yaml
│   │   ├── test-session-namespace.yaml
│   │   └── ...
│   └── manifest.json                # Catalogue + expected outcomes
└── README.md                        # this file
```

## Fixture format

A **byte-level fixture** is a JSON file representing a single LSDP frame as it would appear on the wire (after WebSocket text-frame decoding). The conformance runner :
- Encodes the fixture with the implementation under test
- Decodes back
- Compares to the original (round-trip)

Example `fixtures/envelope/snapshot-basic.json` :

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

A **scenario** is a YAML file describing a sequence of frames exchanged between client and server, plus expected outcomes :

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

To claim "LSDP/1 conformance", an implementation MUST pass all scenarios tagged `required` in `manifest.json`. Optional scenarios (`recommended`, `extended`) measure quality but are not blocking.

| Tag | Scenarios | Required for conformance |
|---|---|---|
| `required` | core protocol behavior, error codes, sequencing, role enforcement | yes |
| `recommended` | reconnect timing, rate limit handling, edge cases | no, but tracked |
| `extended` | performance budgets, large state behaviour | no |

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
