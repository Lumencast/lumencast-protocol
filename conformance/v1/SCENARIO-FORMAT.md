# Scenario format

Each scenario describes a sequence of LSDP message exchanges and expected behaviours, in YAML. A conformance runner replays the steps and verifies the implementation under test conforms.

## File location

```
conformance/v1/scenarios/<scenario-id>.yaml
```

The `<scenario-id>` matches the file name (without extension). Indexed in [`../manifest.json`](../manifest.json).

## Top-level shape

```yaml
name: subscribe-snapshot-delta
description: Basic happy path — subscribe, receive snapshot, receive delta.
tag: required          # required | recommended | extended
target: any            # any | server | runtime
spec_refs:
  - LSDP-1#section-6
  - LSDP-1#section-3.1

steps:
  - <step>
  - <step>
  ...
```

| Field | Required | Description |
|---|---|---|
| `name` | yes | Scenario identifier. MUST match the filename. |
| `description` | yes | One-sentence English summary of what the scenario verifies. |
| `tag` | yes | `required` (must pass for conformance), `recommended` (quality signal), `extended` (corner cases / perf). |
| `target` | yes | `any` (drives both server and runtime), `server` (drives a server, runner acts as client), `runtime` (drives a runtime, runner acts as server). |
| `spec_refs` | no | List of section anchors in the spec docs that this scenario covers. |
| `steps` | yes | Ordered sequence of step objects. |

## Step kinds

Each step is an object with a `kind` field. The runner executes steps in order.

### `client-sends`

The client (operator-side) sends a frame. The runner emits this on behalf of the client.

```yaml
- kind: client-sends
  frame:
    v: 1
    type: subscribe
    token: $TOKEN_OPERATOR
```

Tokens are `$VARIABLE` placeholders resolved by the runner from the `tokens:` section (if any) at the scenario top level. The runner provides default tokens for standard roles.

### `server-sends`

The server sends a frame in response to its **natural protocol behaviour** — a snapshot following a subscribe, a delta echoing an input, an error rejecting a malformed frame. When `target: runtime`, the runner emits this; when `target: server`, the runner expects the server-under-test to emit a matching frame **on its own**.

If the scenario expects a frame that has no natural protocol trigger (e.g. a delta with no preceding `client-sends input`), use [`server-emits`](#server-emits) instead — `server-sends` MUST be reserved for frames the server emits without test orchestration.

```yaml
- kind: server-sends
  frame:
    v: 1
    type: snapshot
    seq: 1
    scene_id: test-scene
    scene_version: sha256:0000000000000000000000000000000000000000000000000000000000000000
    state:
      title: Hello
      count: 0
```

When the runner is in **expect** mode (target: server), `frame` matching follows these rules:

- All literal fields must match exactly.
- `$ANY` placeholder matches any value of any type (used for non-deterministic fields like timestamps).
- `$ANY_HASH` matches any sha256 hash format.
- Field order doesn't matter (JSON object semantics).
- Unknown fields in the actual frame are tolerated (forward compat).
- Missing required fields fail.

### `server-emits`

The runner causes the server to emit a frame, then verifies the wire form matches. Used when the scenario expects a server-driven frame that has no natural protocol trigger — a delta the test author wants to inject as part of a script, not produced by client input or adapter logic.

```yaml
- kind: server-emits
  frame:
    v: 1
    type: delta
    seq: 2
    patches:
      - { path: count, value: 1 }
```

In server-target mode, the runner :

1. Extracts the patches (or scene transition, or other server-driven state change) from `frame`.
2. Triggers the change via the [test control plane](../../interop/CONTROL.md) — typically `POST /test/emit` for deltas.
3. Reads the next frame from the WebSocket.
4. Matches it against `frame` using the same rules as `server-sends`.

In runtime-target mode, `server-emits` is identical to `server-sends` — the runner-as-server simply emits the frame on the wire.

This step kind exists so scenarios can **describe an expected wire frame without specifying its trigger**. Scenarios that test natural server behaviour (snapshot-on-subscribe, delta-after-input) MUST use `server-sends` instead.

`server-emits` currently supports `frame.type: delta` (via `POST /test/emit`). Other frame types — `snapshot`, `scene_changed`, `error`, `pong` — are reserved for future control plane extensions.

### `expect-runtime-state`

Verify the runtime's reactive store matches.

```yaml
- kind: expect-runtime-state
  state:
    title: Hello
    count: 0
```

Only valid when the runner has access to the runtime's state — typically `target: runtime` or `target: any`.

The state shape MUST be a flat dictionary of `LeafPath → JSONValue`. Sub-objects in the expected state are flattened to dotted paths.

### `expect-server-state`

Verify the server's authoritative state matches.

```yaml
- kind: expect-server-state
  state:
    "__inputs.title": World
```

Same shape as `expect-runtime-state`, but for the server side.

### `expect-client-action`

Verify the runtime took an expected action that doesn't directly emit a frame (e.g., closes the WebSocket, attempts a reconnect, sets a status).

```yaml
- kind: expect-client-action
  action: close-with-reason
  reason: VERSION_GAP
```

Defined actions:

| `action` | Meaning | Additional fields |
|---|---|---|
| `close-with-reason` | The runtime closes the WS with a reason string | `reason` |
| `reconnect` | The runtime opens a fresh WS to the same URL | (none) |
| `fetch-bundle` | The runtime issues a HTTP GET for `<scene_version>` bundle | `scene_version` |
| `status-change` | The runtime emits an `onStatus` callback | `status` (one of `disconnected`/`connecting`/`live`) |
| `onError` | The runtime emits an `onError` callback | `code` (matches an `ErrorCode`) |

### `expect-no-frame-for`

Verify no server frame arrives for a duration. Used to test silence (e.g., heartbeat behaviour).

```yaml
- kind: expect-no-frame-for
  duration_ms: 1000
```

### `wait`

Pause the runner for a duration. Used to test time-dependent behaviour (heartbeats, reconnect backoff).

```yaml
- kind: wait
  duration_ms: 500
```

### `set-clock`

Set the test clock to a specific point. Used for time-sensitive scenarios. Implementations that don't support a virtual clock skip steps using this kind (the scenario is then `recommended`, not `required`).

```yaml
- kind: set-clock
  to_ms: 5000
```

### `client-action`

Instruct the runtime under test to perform an action. Distinct from `expect-client-action` (which **verifies** an action), this **drives** one. Used for scenarios that exercise the runtime's API surface beyond what frame exchange covers.

```yaml
- kind: client-action
  action: setToken
  token: $TOKEN_OPERATOR_ROTATED
```

Defined actions :

| `action` | Meaning | Additional fields |
|---|---|---|
| `setToken` | Call `handle.setToken(token)` on the runtime | `token` |
| `disconnect` | Call `handle.disconnect()` | (none) |

A scenario that uses `client-action` is `target: runtime` only — the runner has direct access to the runtime's handle.

## Connection routing modifier

Steps may declare which WebSocket they target via the `on_connection` field. Used by scenarios involving multiple concurrent connections (token rotation).

```yaml
- kind: client-sends
  on_connection: new       # the most recently opened connection
  frame:
    v: 1
    type: subscribe
    token: $TOKEN_OPERATOR_ROTATED
```

| Value | Meaning |
|---|---|
| `original` | The first connection opened in the scenario (default) |
| `new` | The most recently opened connection |
| `<id>` | A named connection if the scenario declares multiple |

When unspecified, steps target `original`. A scenario that opens multiple connections (e.g. token rotation produces a second WebSocket before closing the first) MUST tag the steps that go to the new connection.

## Bundle declarations

Scenarios that exercise scene loading reference test bundles. Two forms :

### Inline bundle

Embed the LSML bundle directly in the scenario YAML. Useful for small, self-contained scenarios.

```yaml
bundles:
  - id: title-bundle
    inline:
      lsml: "1.0"
      scene_id: t
      scene_version: sha256:0000...
      layout:
        kind: text
        bind: { value: "__inputs.title" }
      operator_inputs:
        - path: "__inputs.title"
          label: Title
          type: string
          writable_by: [operator]
      defaults:
        "__inputs.title": ""
```

### File-referenced bundle

Reference a bundle stored under `conformance/v1/bundles/`. Useful for shared bundles used across multiple scenarios.

```yaml
bundles:
  - id: minimal-scoreboard
    path: ../bundles/minimal-scoreboard.lsml.json
```

### Resolution

`$BUNDLE.<id>.hash` resolves to the sha256 of the named bundle. The runner pre-computes hashes by canonicalizing the bundle JSON per LSML 1.0 § 3 (sort keys, no insignificant whitespace, scene_version field set to all-zeros for hashing then replaced).

## Verification semantics

`expect-runtime-state` and `expect-server-state` perform a **subset-match** comparison by default :

- Every path/value listed in the expected state MUST be present in the actual state.
- Extra paths in the actual state are ignored (e.g. `__system.*` paths the server adds automatically).
- Order doesn't matter (dictionary semantics).

For scenarios that need to verify *cleanup* (e.g. old paths are gone after a `scene_changed`), set `mode: exact` :

```yaml
- kind: expect-runtime-state
  mode: exact          # default: subset
  state:
    b: 100
```

In `mode: exact`, the actual state MUST NOT contain any path beyond those listed.

## Tokens & roles

Scenarios commonly need tokens with specific roles. The runner provides standard tokens by default :

| Placeholder | Role | Notes |
|---|---|---|
| `$TOKEN_VIEWER` | viewer | Cannot send `input` |
| `$TOKEN_OPERATOR` | operator | Can write to `__inputs.*` |
| `$TOKEN_SERVICE` | service | Can write to `__inputs.*` constrained by `paths` claim |
| `$TOKEN_TEST` | test | Can write to `__test.*` only |
| `$TOKEN_INVALID` | (none) | Always rejected with `AUTH_DENIED` |

Custom tokens can be declared at the top of the scenario:

```yaml
tokens:
  - placeholder: $TOKEN_SERVICE_NARROW
    role: service
    paths: ["quasar.twitch.*"]
```

## Bundle references

Scenarios that exercise scene loading reference test bundles by path :

```yaml
- kind: server-sends
  frame:
    type: snapshot
    scene_id: test-scene
    scene_version: $BUNDLE.minimal-scoreboard.hash
    state:
      "score.home": 0

bundles:
  - id: minimal-scoreboard
    path: ../bundles/minimal-scoreboard.lsml.json
```

`$BUNDLE.<id>.hash` resolves to the sha256 of the named bundle. The runner pre-computes these.

## Running a scenario

```sh
lumencast conformance --scenario subscribe-snapshot-delta --target runtime --runtime-cmd "node ./build/runtime.js"
lumencast conformance --tag required --target server --server-url ws://localhost:8080
```

The runner:

1. Loads the scenario YAML
2. Resolves placeholders ($TOKEN_*, $BUNDLE.*)
3. For each step, executes per the kind's semantics
4. Records pass/fail per step
5. Exits 0 on all-pass, 1 on first failure (or with `--continue`, exits 1 after all run)

## Authoring scenarios

A scenario should:

- Cover **one** behaviour cleanly. Compound scenarios are harder to debug.
- Use the standard token placeholders unless the test specifically needs custom ones.
- Reference bundles by id, not inline (keeps scenario YAMLs readable).
- Tag accurately — `required` is reserved for behaviours mandated by the spec; everything else is `recommended` or `extended`.
- Include `spec_refs` linking to the relevant spec section so a reader can audit conformance is right-shaped.

## Validating a scenario

```sh
lumencast validate-scenario conformance/v1/scenarios/<id>.yaml
```

Checks the YAML against the format described here. CI runs this on every change to `conformance/v1/scenarios/`.
