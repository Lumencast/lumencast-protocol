# Interop test control plane (LSDP/1)

**Status** : DRAFT — published alongside `lumencast-protocol` v0.1, refined in lockstep with the first cross-language interop runs.

This document specifies the HTTP control plane that LSDP/1 server implementations expose to enable **cross-language conformance testing**. The control plane is a test-only side channel that lets an external harness (typically running in a different language) drive deterministic scenarios against a live server.

The control plane is **never exposed in production**. It MUST be off by default and only activated by an explicit flag (e.g. `--test-control-port`).

---

## Why this exists

The LSDP/1 conformance scenarios at `conformance/v1/scenarios/` are bidirectional scripts. Many of them fix the exact frames the server is expected to emit — e.g. `subscribe-snapshot-delta` requires the server to send a snapshot whose `state` is exactly `{title: "Hello", count: 0}`.

When the harness and the server are written in the same language, the harness can prime the server's internal state programmatically (via Go's `Driver` interface, etc.). For cross-language testing, that coupling is impossible. The control plane fills the gap with a small HTTP API that mirrors the in-process `Driver` contract exactly.

A server implementation that exposes this control plane can be driven by any harness in any language. The matrix of M servers × N harnesses collapses from M×N implementations down to M+N implementations of one shared contract.

---

## Endpoints

All endpoints are JSON over HTTP/1.1. Bodies are UTF-8. Errors return RFC 7807 `application/problem+json` with HTTP 4xx/5xx status. The control plane MUST listen on a separate port from the LSDP/1 WebSocket endpoint so production servers can omit the binding entirely.

### `POST /test/setup`

Resets the server to a clean state and prepares it for one scenario.

Request body:

```json
{
  "scenario": "subscribe-snapshot-delta",
  "tokens": {
    "$TOKEN_OPERATOR": "tok-op-1",
    "$TOKEN_VIEWER":   "tok-vw-1",
    "$TOKEN_SERVICE":  "tok-svc-1",
    "$TOKEN_TEST":     "tok-test-1"
  },
  "bundles": [
    {
      "id": "t",
      "hash": "sha256:f1d2d2f924e986ac86fdf7b36c94bcdf32beec15c3aef0d27b6bc8f8a90b9e3f",
      "inline": { "v": 1, "kind": "frame", "id": "t", "state": { "title": "Hello", "count": 0 } }
    }
  ],
  "initial_state": {
    "title": "Hello",
    "count": 0
  }
}
```

Response : `200 OK` with body :

```json
{
  "ws_url": "ws://127.0.0.1:8081/lsdp.v1",
  "scene_id": "t",
  "scene_version": "sha256:f1d2d2f924e986ac86fdf7b36c94bcdf32beec15c3aef0d27b6bc8f8a90b9e3f"
}
```

The server :

1. Drops every existing scene
2. Registers a fresh scene named `bundles[0].id` (the canonical scenario bundle)
3. Pins its `scene_version` to `bundles[0].hash`
4. Parses `bundles[0].inline` for scene metadata (see "Inline bundle parsing" below)
5. Initialises the scene state from `initial_state` (or `inline.defaults` if `initial_state` is absent)
6. Re-installs token recognition so the placeholder map matches the request
7. Returns the WebSocket URL the harness should dial for this scenario

Multiple bundles MAY be declared ; the first is the active scene, additional bundles are made available for `bundle-incompatible` style negotiation. Servers that do not support bundle negotiation respond `200 OK` and ignore the extras.

#### Robustness

Servers MUST accept `null`, omitted, or `[]`/`{}` for any of `tokens`, `bundles`, `initial_state` and treat them as empty. Cross-language harnesses serialise empty maps as `null` in some languages ; rejecting these as 422 makes scenarios with no seeded state (auth rejection, envelope errors) fail to even start.

#### Inline bundle parsing

`bundles[i].inline` is the inline LSML body. Servers SHOULD extract the following fields when present and apply them to the registered scene :

| Field | Purpose |
|---|---|
| `inline.scene_id` | When present, MUST override `bundles[i].id` for the scene's emitted `scene_id` (the bundle's `id` field is the scenario-local reference, used for `$BUNDLE.<id>.hash` placeholder resolution). |
| `inline.operator_inputs` | List of `{path, type, constraints}` objects. The server MUST enforce path declaredness (reject input frames targeting undeclared paths with `UNKNOWN_PATH`) and apply the constraints (`maxLength`, `min`/`max`, `values`) per LSML 1.0 § 8. |
| `inline.defaults` | Map of `path → value`. Used as the scene's initial state when `initial_state` is empty. |

Servers that do not support a given field SHOULD ignore it and continue. Scenarios that depend on enforcement (`invalid-value-rejected`, `unknown-path-rejected`) will fail against such servers, surfacing the gap at the matrix level.

### `POST /test/reset`

Drops every scene and clears every connection. Idempotent. Response : `204 No Content`.

The harness MUST call `/test/reset` between scenarios if it does not call `/test/setup` (which already implies a reset).

### `GET /test/state`

Returns a snapshot of the active scene's authoritative state. Used by `expect-server-state` steps.

Response :

```json
{
  "scene_id": "t",
  "scene_version": "sha256:f1d2d2f9...",
  "state": {
    "title": "Hello",
    "count": 0
  }
}
```

If no scene is active (no `/test/setup` since the last `/test/reset`), respond `409 Conflict`.

### `POST /test/emit`

Schedules a server-driven delta. Used by the [`server-emits`](../conformance/v1/SCENARIO-FORMAT.md#server-emits) scenario step kind to script frames that have no natural protocol trigger (e.g. a delta the test author wants to inject without simulating an operator input). The harness calls this immediately before reading the next frame from the WebSocket.

Request body :

```json
{
  "patches": [
    { "path": "count", "value": 1 },
    { "path": "title", "value": "Updated" }
  ]
}
```

The server MUST emit the resulting delta as a single LSDP/1 `delta` frame to every subscriber whose subscription matches. Response : `204 No Content`.

If the active scene rejects the patch (unknown path, invalid value), the server responds `400 Bad Request` with the LSDP/1 error code in the body :

```json
{
  "code": "INVALID_VALUE",
  "message": "count expects number, got string",
  "path": "count"
}
```

### `GET /test/health`

Liveness probe. Returns `200 OK` with body `{"status":"ok","control_plane_version":1}`.

---

## Token vocabulary

The conformance scenarios use these placeholders (replaced by the harness before sending). Servers SHOULD recognise the tokens supplied via `/test/setup` for these placeholders :

| Placeholder | Role | Notes |
|---|---|---|
| `$TOKEN_OPERATOR` | operator | full access including `input` frames |
| `$TOKEN_VIEWER` | viewer | read-only |
| `$TOKEN_SERVICE` | service | server-to-server bridges |
| `$TOKEN_TEST` | test | test-mode only, may have elevated debug access |
| `$TOKEN_INVALID` | (none) | always rejected — used by negative scenarios |

Servers MUST reject `$TOKEN_INVALID` with the `auth-denied` close code regardless of the supplied token map. If the harness sends an explicit value for `$TOKEN_INVALID` in `/test/setup`, the server MUST ignore it.

---

## Discovery

The interop driver discovers the control plane via the canonical CLI flag :

```
<sdk-cli> serve-scenario --test-control-port 9000 --ws-port 8081
```

Both ports are mandatory and arbitrary — the driver picks free ports per scenario to allow parallelism. The CLI prints the resolved URLs on stdout in a stable JSON line :

```json
{"control_url":"http://127.0.0.1:9000","ws_url":"ws://127.0.0.1:8081/lsdp.v1"}
```

The driver waits for that line on stdout, then proceeds. Servers MUST flush this line before listening for connections.

---

## Conformance

A server implementation is **interop-conformant** when :

1. The control plane endpoints respond as specified above for every scenario in `conformance/v1/scenarios/` (within the scenarios it claims to support — `target: server` or `target: any`).
2. Scenarios run via this control plane produce identical observable output (modulo timing) to scenarios run via the in-process `Driver` interface in the SDK's own test suite.
3. The CLI prints the discovery line on stdout before accepting connections.
4. The control plane is OFF by default and only activated by an explicit flag.

A harness implementation is **interop-conformant** when :

1. It can drive any server exposing this control plane through every scenario in `conformance/v1/scenarios/` (within the scenarios it claims to support — `target: any` or `target: runtime` for the harness side).
2. Failed `/test/setup` or `/test/reset` calls are reported as harness errors, not as scenario failures.
3. The harness does not rely on any in-process state of the server beyond the control plane responses.

---

## Versioning

The control plane is versioned independently of LSDP/1. The current version is reported by `/test/health` as `control_plane_version: 1`. Backwards-incompatible changes bump the major version and add new endpoint paths (`/test/v2/setup`, etc.). Implementations MAY support multiple versions concurrently.

The control plane spec is governed by the same RFC process as LSDP/1 (see `RFC-PROCESS.md`). Changes that affect any of the four endpoints above require an RFC.
