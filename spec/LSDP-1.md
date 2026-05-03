# LSDP/1 — Leaf State Delta Protocol, version 1

> **Status** : 1.1 — additive over 1.0.1. Adds incremental resume, per-leaf animation directives, frame provenance, show-level scene transitions, ping/pong correlation, optimistic-UI input correlation, and a clean unsubscribe frame. Every addition is optional ; 1.0 receivers ignore the new fields. Subprotocol bumps to `lsdp.v1.1` (1.0 connections still negotiate `lsdp.v1`).
>
> **Conformance keyword convention** : the words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, **MAY** are used as defined in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

LSDP is the wire protocol that Lumencast servers and runtimes speak over WebSocket. It pushes typed state deltas at leaf-grain from a server to a passive client, with sequenced delivery, gap detection, snapshot recovery, and bounded reconnection.

---

## Table of contents

1. [Transport](#1-transport)
2. [Envelope](#2-envelope)
3. [Frames — server to client](#3-frames--server-to-client)
4. [Frames — client to server](#4-frames--client-to-server)
5. [Sequencing](#5-sequencing)
6. [Subscription lifecycle](#6-subscription-lifecycle)
7. [Reconnection](#7-reconnection)
8. [Authentication & token rotation](#8-authentication--token-rotation)
9. [Roles & write authority](#9-roles--write-authority)
10. [Reserved namespaces](#10-reserved-namespaces)
11. [Error handling](#11-error-handling)
12. [Heartbeat](#12-heartbeat)
13. [Versioning & compatibility](#13-versioning--compatibility)
14. [Security considerations](#14-security-considerations)
15. [Conformance](#15-conformance)
16. [LeafPath grammar](#16-leafpath-grammar)
17. [Subscription state machine](#17-subscription-state-machine)
18. [Incremental resume](#18-incremental-resume-11) (1.1+)

## 1. Transport

LSDP/1 runs over **WebSocket** (RFC 6455) only. Other transports (HTTP/3, QUIC, raw TCP) are out of scope for v1.

### 1.1 Subprotocol negotiation

The WebSocket subprotocol negotiation MUST set the `Sec-WebSocket-Protocol` header to one of the LSDP/1.x subprotocol tokens (see §13.2). Clients SHOULD advertise every minor they support, highest first :

```
Sec-WebSocket-Protocol: lsdp.v1.1, lsdp.v1
```

Servers MUST select the highest token they support and echo it in the response. Servers MUST reject upgrade requests that advertise no LSDP subprotocol with HTTP 426 (Upgrade Required).

### 1.2 Frame encoding

WebSocket text frames are used for all messages. Binary frames are reserved and MUST NOT be sent in LSDP/1.

Each text frame contains exactly one LSDP envelope encoded as JSON (RFC 8259) with UTF-8.

## 2. Envelope

Every message — in either direction — has the same outer shape:

```json
{
  "v": 1,
  "type": "<frame-type>",
  ...
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `v` | integer | yes | Protocol major version. MUST be `1`. |
| `type` | string | yes | Frame type discriminator (see §3, §4). |
| `seq` | integer | server frames only | Monotonically increasing sequence number, starts at 1 per subscription. |
| `ts` | string (ISO 8601 UTC, RFC 3339 profile) | optional | Server-generated timestamp for diagnostics. MAY be sent on any server frame ; receivers MUST tolerate its absence and MUST NOT use it for ordering (use `seq` instead). |

Receivers MUST ignore unknown top-level fields (forward compatibility).

Receivers MUST reject envelopes where `v != 1` with an `INTERNAL` error and close the connection.

## 3. Frames — server to client

### 3.1 `snapshot`

The full state of the subscription at a point in time. Server emits exactly one `snapshot` per subscription, immediately after a successful `subscribe`. Reconnection or `scene_changed` triggers a new `snapshot`.

```json
{
  "v": 1,
  "type": "snapshot",
  "seq": 1,
  "scene_id": "main-stage",
  "scene_version": "sha256:abc123...",
  "state": {
    "show.title": "Live Now",
    "players.0.name": "Alice",
    "players.0.score": 0,
    "players.1.name": "Bob",
    "players.1.score": 0
  }
}
```

| Field | Required | Description |
|---|---|---|
| `scene_id` | yes | Identifier of the active scene |
| `scene_version` | yes | Content hash of the LSML bundle the runtime MUST fetch and use for rendering |
| `state` | yes | Map of `LeafPath → JSONValue` — the complete state at this snapshot moment |

The `state` map MUST be a flat dictionary of leaf paths. It MUST NOT contain nested objects whose keys overlap with declared scene paths.

### 3.2 `delta`

Incremental patches to apply to the existing state. `delta` frames MUST follow a `snapshot` frame in the same connection.

```json
{
  "v": 1,
  "type": "delta",
  "seq": 42,
  "patches": [
    { "path": "players.0.score", "value": 7,
      "transition": { "kind": "tween", "duration_ms": 200, "easing": "ease-out" } },
    { "path": "show.title", "value": "Match Point" }
  ],
  "cause": { "source": "operator:user-abc", "input_id": "ui-9f3a" }
}
```

| Field | Required | Description |
|---|---|---|
| `patches` | yes | Non-empty array of `{path, value, transition?}` patches. Order matters: applied left-to-right. |
| `cause` | optional (1.1+) | Provenance of this delta. See §3.2.2. |

#### 3.2.2 Per-leaf transition directive (1.1+)

A patch MAY carry an optional `transition` object instructing the runtime how to interpolate from the leaf's current rendered value to the new one. The shape is :

```json
{
  "kind": "tween" | "spring" | "snap",
  "duration_ms": <integer>,
  "easing": "linear" | "ease-in" | "ease-out" | "ease-in-out" | "spring",
  "stiffness": <number>,
  "damping": <number>,
  "mass": <number>
}
```

| Field | Required | Description |
|---|---|---|
| `kind` | yes | `tween` (time-based curve), `spring` (physics simulation), or `snap` (no interpolation, instant — useful to cancel an in-flight animation). |
| `duration_ms` | required for `tween` | Animation duration in milliseconds. |
| `easing` | required for `tween` | One of the listed curves. |
| `stiffness` / `damping` / `mass` | required for `spring` | Spring physics parameters per LSML 1.0.1 §6.2 (damped harmonic oscillator). |

The runtime SHOULD apply the transition only when the bound primitive's animatable property accepts the value type (numbers and CSS colors interpolate ; arbitrary strings snap). Unsupported transitions MUST degrade to instant application without raising an error.

A 1.0 receiver ignores the field — the patch is applied instantly. This is forward-compatible by design.

#### 3.2.3 Provenance (`cause`, 1.1+)

A delta MAY carry an optional `cause` object describing what triggered the state change. It is debug- and audit-only — receivers MUST NOT use it for semantic decisions.

```json
{ "source": "operator:user-abc", "input_id": "ui-9f3a" }
```

| Field | Required | Description |
|---|---|---|
| `source` | yes (when cause is present) | Free-form string identifying the origin. Conventional prefixes: `operator:<user>`, `service:<name>`, `adapter:<kind>`, `system:<reason>`. |
| `input_id` | optional | Echoes the `client_msg_id` from the originating `input` frame (§4.2), allowing optimistic-UI correlation. |

A 1.0 receiver ignores the field.

A single `delta` frame is atomic from the runtime's perspective — all patches MUST be applied before the runtime renders the next frame.

#### 3.2.1 Allowed `value` types

`value` MUST be one of:

- JSON `string`
- JSON `number` (integer or finite floating-point ; `NaN` and `Infinity` are forbidden)
- JSON `boolean`
- JSON `null`
- JSON `array` whose elements are themselves any of the allowed types (recursive)

JSON `object` is **forbidden** in `value`. To update a nested structure, push leaf-grain patches against the descendant paths instead.

Composite domain types (color, point, dimensions, etc.) MUST be encoded as a primitive type :

- color → CSS-hex `string`, e.g. `"#rrggbb"` or `"#rrggbbaa"`
- point / coordinate → 2-element `array` of numbers, e.g. `[x, y]`
- dimensions → 2-element `array`, e.g. `[w, h]`
- enum → `string` matching the bundle's declared `values` list

A patch with a forbidden `value` type MUST be rejected with `INVALID_VALUE` and MUST NOT be applied.

### 3.3 `scene_changed`

The active scene has been swapped server-side. The runtime MUST refetch the bundle at `scene_version`, seed a new store, render a new tree, and crossfade. The runtime MUST receive a new `snapshot` frame after this — sequence resets to 1.

```json
{
  "v": 1,
  "type": "scene_changed",
  "seq": 100,
  "from_scene_id": "main-stage",
  "scene_id": "intermission",
  "scene_version": "sha256:def456...",
  "transition": { "kind": "crossfade", "duration_ms": 600 }
}
```

| Field | Required | Description |
|---|---|---|
| `seq` | yes | Sequence (resets in the following snapshot). |
| `scene_id` | yes | The destination scene id. |
| `scene_version` | yes | Content hash of the destination bundle. |
| `from_scene_id` | optional (1.1+) | The previously active scene id. Allows the runtime to render a show-level transition that needs to know both endpoints (e.g. layered crossfade). 1.0 receivers ignore. |
| `transition` | optional (1.1+) | Show-level transition the runtime SHOULD use between the old and new scene trees. See §3.3.1. 1.0 receivers ignore — they crossfade per their default. |

After a `scene_changed`, the next server frame MUST be a `snapshot` for the new scene with `seq = 1`. Any `delta` between the `scene_changed` and the `snapshot` is undefined behavior — receivers SHOULD discard.

#### 3.3.1 Show-level transition spec (1.1+)

The `transition` object is the same shape as the per-leaf `transition` from §3.2.2, with one additional `kind` value :

```json
{ "kind": "crossfade", "duration_ms": 600 }
{ "kind": "tween", "duration_ms": 400, "easing": "ease-in-out" }
{ "kind": "snap" }
```

| `kind` | Semantics |
|---|---|
| `crossfade` | Both trees rendered simultaneously, opacity transitions from 100% old / 0% new to 0% old / 100% new over `duration_ms`. |
| `tween` | The runtime applies the curve to whatever continuity exists between the old and new tree (e.g. shared element transitions on matching scene_id paths). |
| `spring` | Same as `tween` but spring physics. |
| `snap` | No transition — the new tree replaces the old instantly. |

Runtimes that do not support a given `kind` SHOULD fall back to `crossfade` (the runtime's default scene transition).

### 3.4 `error`

A recoverable or fatal error condition. After an `error` frame, the server MAY close the connection. The runtime SHOULD propagate the error to its `onError` callback.

```json
{
  "v": 1,
  "type": "error",
  "seq": 50,
  "code": "WRITE_FORBIDDEN",
  "message": "viewer role cannot send input frames",
  "recoverable": false,
  "path": "__inputs.title"
}
```

| Field | Required | Description |
|---|---|---|
| `code` | yes | Error code from the closed taxonomy (see [ERROR-CODES.md](ERROR-CODES.md)) |
| `message` | yes | Human-readable description, English |
| `recoverable` | yes | Boolean. `true` if the runtime can attempt to continue (e.g. retry with a fresh token), `false` if the runtime should disconnect. |
| `path` | conditional | The leaf path the error applies to. REQUIRED for `WRITE_FORBIDDEN`, `UNKNOWN_PATH`, `INVALID_VALUE`. Forbidden for codes that are not path-scoped. |

#### 3.4.1 Per-code extra fields

Some error codes carry additional structured fields. The set is closed per code — receivers MAY ignore unknown fields, but emitters MUST NOT carry fields beyond those listed here without bumping the LSDP minor version.

| Code | Extra fields | Type | Required | Description |
|---|---|---|---|---|
| `WRITE_FORBIDDEN` | `path` | LeafPath | yes | The path the rejected write targeted |
| `UNKNOWN_PATH` | `path` | LeafPath | yes | The undeclared path the input frame referenced |
| `INVALID_VALUE` | `path` | LeafPath | yes | The path whose value violated its constraint |
| `RATE_LIMIT` | `retry_after_ms` | integer | no | Earliest moment in milliseconds when the client SHOULD retry |
| `BUNDLE_INCOMPATIBLE` | `requested_version` | string | no | The LSML major version the bundle declared |
| `BUNDLE_INCOMPATIBLE` | `supported_version` | string | no | The LSML major version the runtime supports |
| `TEST_SESSION_EXPIRED` | `session` | string | no | The session UUID that expired |

All other codes carry only the base envelope (`v / type / seq / code / message / recoverable`).

### 3.5 `pong`

Heartbeat reply. See §12.

```json
{ "v": 1, "type": "pong", "nonce": "abc-9f3a" }
```

| Field | Required | Description |
|---|---|---|
| `nonce` | optional (1.1+) | Echoes the `nonce` field of the matching `ping` frame (§4.3) verbatim. Lets the sender correlate the response to a specific ping when latency-probing or timing health checks. 1.0 receivers ignore. |

## 4. Frames — client to server

### 4.1 `subscribe`

Sent immediately after WebSocket open. Identifies the client and the subscription target.

```json
{
  "v": 1,
  "type": "subscribe",
  "token": "<auth-token>",
  "scene": "main-stage",
  "session": null,
  "since_sequence": 12345
}
```

| Field | Required | Description |
|---|---|---|
| `token` | yes | Opaque authentication token. Server validates and assigns role. |
| `scene` | conditional | Required for **test mode** (subscribe to a specific scene under preview). Forbidden for **live mode** (server picks the active scene). |
| `session` | conditional | Required for **test mode** with isolated session, forbidden otherwise. |
| `since_sequence` | optional (1.1+) | Last `seq` the client successfully observed before disconnect. Server replies with deltas resuming from that point if its replay buffer covers the gap, otherwise with a fresh `snapshot` and the client discards its cached state. See §18 (incremental resume). 1.0 servers MUST ignore this field and always respond with `snapshot`. |

Server MUST respond with either `snapshot` (success), a `delta` stream resuming from `since_sequence + 1` (success, 1.1+ only), or `error` (failure).

### 4.2 `input`

Mutate operator inputs. Allowed only for clients with `operator` or `service` role. Forbidden for `viewer` role.

```json
{
  "v": 1,
  "type": "input",
  "patches": [
    { "path": "__inputs.show_title", "value": "New title" },
    { "path": "__inputs.show_visible", "value": true }
  ],
  "client_msg_id": "ui-9f3a"
}
```

| Field | Required | Description |
|---|---|---|
| `patches` | yes | Non-empty array of `{path, value}` patches |
| `client_msg_id` | optional (1.1+) | Free-form identifier the client uses to correlate the resulting `delta` echo with the original input. The server MUST echo this value verbatim in the `cause.input_id` of the delta it produces in response (see §3.2.2). Used for optimistic UI : a client tags its own emit, then matches the echo and reconciles its predicted state against the authoritative one. 1.0 servers MUST ignore this field and emit deltas without `cause`. |

Server MUST validate each patch against the active scene's `operator_inputs` declaration:

- Unknown path → `error { code: UNKNOWN_PATH }`, MUST NOT apply any patch
- Type mismatch → `error { code: INVALID_VALUE }`, MUST NOT apply any patch
- Path not in `__inputs.*` namespace and not in `__test.*` (for test sessions) → `error { code: WRITE_FORBIDDEN }`

Successful inputs are reflected back to **all** subscribers as a `delta` (the client that sent the `input` will see its own change applied via `delta`).

### 4.3 `ping`

Heartbeat. See §12.

```json
{ "v": 1, "type": "ping", "nonce": "abc-9f3a" }
```

| Field | Required | Description |
|---|---|---|
| `nonce` | optional (1.1+) | Free-form correlation identifier. The receiver MUST echo it verbatim in the `pong` reply (§3.5). 1.0 receivers reply with a bare `pong` and the sender treats absent-nonce as "match the most recent ping". |

### 4.4 `unsubscribe` (1.1+)

Clean teardown signal. The client tells the server it is done with this subscription ; the server MUST close the WebSocket within 1 second. No data flows after `unsubscribe`.

```json
{ "v": 1, "type": "unsubscribe" }
```

This frame is purely a courtesy — the WebSocket close itself is the canonical signal. `unsubscribe` exists for two reasons :

1. It lets the server distinguish a clean disconnect (no auto-reconnect on the client side) from a network-level close (which may indicate a glitch worth retrying).
2. It lets the server flush its replay buffer for that connection earlier than waiting for TCP/WebSocket close timeout.

1.0 servers MUST tolerate the frame (since "ignore unknown frame types" is a 1.0 conformance rule), but they need not change their behaviour — the WebSocket close that follows is the actual teardown signal.

## 5. Sequencing

Server frames carry a monotonically increasing `seq` integer, starting at `1` for the `snapshot` after a successful `subscribe`. The sequence resets to `1` after each `scene_changed` (the next `snapshot` is `seq=1`).

Frame types and `seq`:

| Frame | Carries `seq` | Notes |
|---|---|---|
| `snapshot` | yes | `seq = 1` initially or after `scene_changed` |
| `delta` | yes | `seq = previous_seq + 1` |
| `scene_changed` | yes | `seq = previous_seq + 1`. The following `snapshot` resets to `seq = 1`. |
| `error` | yes | `seq = previous_seq + 1` |
| `pong` | no | Heartbeats are out-of-band |

The runtime MUST track the last `seq` it observed. If the runtime receives a frame with `seq > last_seq + 1` (a gap), it MUST close the WebSocket and reconnect (which will trigger a fresh `snapshot`). Emit a `VERSION_GAP` reason in the close frame.

The runtime MUST tolerate `seq <= last_seq` (a replay) by dropping the duplicate frame silently.

### 5.1 `error` frames before any `snapshot`

When the server rejects `subscribe` (e.g. `AUTH_DENIED`, `SCENE_NOT_FOUND`, `VERSION_MISMATCH`) the resulting `error` frame is emitted **before** any `snapshot`. In this case `seq = 1` (not `previous_seq + 1`, since `previous_seq = 0`). The runtime MUST accept this and MUST NOT classify it as a gap.

Subsequent server frames after a recoverable pre-snapshot error are undefined ; the server SHOULD close the connection (per §11) and the runtime SHOULD treat the connection as terminal.

## 6. Subscription lifecycle

```
Client                                  Server
  |                                       |
  |---- WebSocket open  --------------->  |
  |     (Sec-WebSocket-Protocol:          |
  |      lsdp.v1)                         |
  |                                       |
  |---- subscribe(token, scene?) ------>  |
  |                                       | validates token, scene, session
  |                                       |
  |<--- snapshot(seq=1, ...) -----------  |
  |                                       |
  |     <runtime fetches bundle           |
  |      at scene_version,                |
  |      seeds store, renders>            |
  |                                       |
  |<--- delta(seq=2, ...) --------------  |
  |<--- delta(seq=3, ...) --------------  |
  |---- input(...) -------------------->  |
  |<--- delta(seq=4, ...) --------------  |  (echo of input)
  |       :                               |
  |<--- scene_changed(seq=N, ...) -----   |
  |<--- snapshot(seq=1, ...) -----------  |  (new scene, seq reset)
  |       :                               |
  |---- WebSocket close ---------------> |
```

A subscription is bound to a single WebSocket connection. Closing the WebSocket terminates the subscription. Servers MUST NOT multiplex multiple subscriptions on a single connection.

## 7. Reconnection

The runtime is responsible for reconnection logic. The protocol does not provide resumption — every reconnect produces a fresh `snapshot`.

Reference reconnect schedule (runtimes MAY vary, MUST be bounded):

| Attempt | Backoff |
|---|---|
| 1 | 0 ms (immediate) |
| 2 | 500 ms |
| 3 | 1 s |
| 4 | 2 s |
| 5 | 4 s |
| 6+ | 8 s, 15 s, 30 s, 60 s (cap) |

The runtime SHOULD jitter each backoff by ±25% to avoid thundering herd.

The runtime MUST cap reconnection attempts at the maximum backoff (default 60 s) — never give up entirely, but do not amplify load on a struggling server.

After a successful reconnect (snapshot received), the runtime MUST:
1. Discard the previous store (the snapshot is the new truth)
2. Reset the `seq` tracker
3. If the new `scene_version` differs from before, refetch the bundle and crossfade
4. Resume `delta` processing

## 8. Authentication & token rotation

LSDP is **token-agnostic**. The `token` field in `subscribe` is an opaque string that the server validates by whatever mechanism it chooses (JWT, opaque bearer, mTLS-derived identity, custom).

The server's validation result MUST yield a role for the connection (see §9).

### Token rotation without disconnect

A client MAY refresh its credential without dropping the WebSocket — this is preferred for long-lived broadcasts.

The runtime calls `setToken(newToken)` (runtime API, see RUNTIME-API.md). The runtime MUST:

1. Open a new WebSocket with the new token
2. Wait for the new `snapshot`
3. Compare the new snapshot's `scene_version` with the current one (see §8.1 below)
4. Atomically replace the active connection's store with the new snapshot's state
5. Close the old WebSocket

This produces zero rendering interruption for the user.

#### 8.1 `scene_version` mismatch during rotation

The new token MAY land on a server whose active scene has changed since the original connection. Two cases :

- **Same `scene_version`** (most common) : steps 4–5 are a pure store swap, no re-render.
- **Different `scene_version`** : the runtime MUST treat the rotation as an implicit `scene_changed` — refetch the bundle at the new `scene_version`, seed a new render tree, crossfade per the runtime's normal scene transition behaviour. Old WebSocket closes after the new tree is mounted.

The runtime MUST NOT abandon the rotation in this case ; the user's new credential is the source of truth.

#### 8.2 Role downgrade during rotation

The server MUST NOT make the runtime's role on the new connection differ from the role implied by the new token. If the new token grants a downgraded role mid-broadcast, the server SHOULD send an `error { code: AUTH_DENIED }` and close.

## 9. Roles & write authority

Each connection has exactly one role, determined by token validation:

| Role | Receives | Can send `input` | Can use `__test.*` |
|---|---|---|---|
| `viewer` | snapshot, delta, scene_changed | no | no |
| `operator` | snapshot, delta, scene_changed | yes (`__inputs.*` only) | no |
| `service` | snapshot, delta, scene_changed | yes (`__inputs.*` only, scoped via `paths` claim) | no |
| `test` | snapshot, delta, scene_changed | yes (`__test.*` only) | yes |

The role is communicated implicitly through enforcement — there is no `role` frame. A client that attempts an action above its role gets a `WRITE_FORBIDDEN` error.

`service` tokens MAY carry a `paths` claim that further restricts which `__inputs.*` sub-paths they can write. The server MUST enforce this restriction.

## 10. Reserved namespaces

LSDP reserves four leaf-path namespaces. The contract for each is normative — implementations MUST NOT deviate.

| Namespace | Purpose | Writable by | Visibility |
|---|---|---|---|
| `__inputs.*` | Operator inputs (declared in LSML `operator_inputs`) | `operator`, `service` (subject to role scope) | All subscribers receive snapshot + delta |
| `__system.*` | Server-emitted system state (adapter health, connection count, scene metadata) | server only — clients MUST NOT write | All subscribers receive snapshot + delta. Concrete keys are listed in §10.1. |
| `__test.*` | Test session sandbox | `test` role only, only in test sessions | Only the originating test session sees these patches ; never propagated to live subscribers |
| `__schema.*` | Reserved for future introspection use | undefined in LSDP/1 — MUST NOT be written by any role | LSDP/1 servers MUST NOT emit paths under this namespace ; runtimes MAY ignore them silently if observed |

Any path starting with `__` and not in this list is **reserved** and MUST NOT be used. LSDP minor versions may register additional namespaces via the same RFC process as new error codes.

User-defined paths MUST NOT start with `__`.

### 10.1 `__system.*` registered keys

Servers SHOULD emit the following system keys when applicable. Runtimes MAY consume them. Future minor versions MAY register additional keys here.

| Path | Type | Description |
|---|---|---|
| `__system.adapter.<adapter_id>.healthy` | boolean | Adapter is currently emitting deltas successfully |
| `__system.adapter.<adapter_id>.last_emit_ts` | string (ISO 8601) | Timestamp of the last delta the adapter produced |
| `__system.subscribers.count` | integer | Current subscriber count on the active scene |
| `__system.scene.applied_seq` | integer | Last `seq` the server applied authoritatively |

Any other key under `__system.*` is implementation-defined and SHOULD be documented by the server vendor.

## 11. Error handling

All errors flow through the `error` frame (§3.4). The complete error code taxonomy is in [ERROR-CODES.md](ERROR-CODES.md).

After an `error` with `recoverable: false`, the server MUST close the WebSocket within 1 second.

After an `error` with `recoverable: true`, the connection MAY continue. The runtime SHOULD log the error and surface it to its `onError` callback.

## 12. Heartbeat

Either side MAY send `ping` to test liveness. The receiver MUST reply with `pong` within 5 seconds.

The runtime SHOULD send `ping` every 30 seconds when the connection is otherwise quiet (no deltas observed in the last 30 s).

The server MAY use the WebSocket-level ping/pong (RFC 6455 §5.5) instead — both are acceptable.

If a `ping` does not receive a `pong` within 5 s, the sender SHOULD treat the connection as dead and reconnect.

## 13. Versioning & compatibility

LSDP uses a **major/minor** scheme.

- **Major** (LSDP/1, LSDP/2) — breaking changes to envelope, frame shape, or semantics. Coexistence supported for 2 major versions: a server SHOULD support the previous major in parallel for 12 months after publishing a new major.
- **Minor** (LSDP/1.0, 1.1, 1.2) — backward-compatible additions (new optional envelope fields, new frame types that older clients can ignore via the "ignore unknown" rule).

### 13.1 Wire-level major version

The `v: 1` envelope field is the **major**. It is checked on every frame.

A client that receives a frame with `v != <its supported major>` MUST close the connection with WebSocket code 1002 (Protocol Error) and surface `VERSION_MISMATCH`.

A server that receives a `subscribe` from a `v: 2` client while only supporting `v: 1` MUST close the WebSocket with code 1002.

### 13.2 Subprotocol-level minor version

Minor versions are signaled at WebSocket subprotocol negotiation time, not in the envelope. Each minor gets a distinct subprotocol token :

- LSDP/1.0 → `lsdp.v1`
- LSDP/1.1 → `lsdp.v1.1`
- LSDP/1.2 → `lsdp.v1.2`
- LSDP/2.0 → `lsdp.v2`

Clients that support multiple minor versions advertise the full list in `Sec-WebSocket-Protocol`, highest preferred first :

```
Sec-WebSocket-Protocol: lsdp.v1.2, lsdp.v1.1, lsdp.v1
```

Servers MUST select the highest minor in their supported set and echo it in the response (RFC 6455 §1.3). The negotiated subprotocol is the connection's effective minor version for its lifetime.

A client and server that agree on `lsdp.v1` (1.0) MUST NOT use any 1.1+ feature on the connection. A client that ignores this and emits a 1.1-only field gets `INTERNAL` (or behavior-defined response from a 1.0 server).

### 13.3 Forward compatibility within a major

A client compatible with LSDP/1.0 MUST be forward-compatible with LSDP/1.x by ignoring unknown envelope fields and unknown frame types.

A client that receives a frame type it does not recognize MUST ignore it silently. A client that receives a known frame with unknown fields MUST ignore those fields and process the rest.

### 13.4 Subprotocol selection failure

If the client offers only subprotocols the server does not support, the server MUST reject the WebSocket upgrade with HTTP 426 Upgrade Required (per §1).

## 14. Security considerations

### 14.1 Token confidentiality

The `token` is sent in plaintext inside the WebSocket frame. WebSocket connections MUST be `wss://` (TLS). Plaintext `ws://` is allowed only on localhost for development and MUST NOT be used in production.

### 14.2 Replay protection

LSDP does not provide replay protection at the protocol level. Tokens SHOULD have short expiration (≤ 1 hour) or single-use semantics where appropriate. Servers MAY also bind tokens to client IPs.

### 14.3 Backpressure & DoS

Servers MUST rate-limit `input` frames per connection. The default rate is 60 inputs/second per connection (averaged over a 1-second sliding window). Exceeding the rate triggers a `RATE_LIMIT` error frame. The server MAY include a `retry_after_ms` field in the error to advise the client when to retry (see §3.4.1).

Servers MAY publish their effective limit in `__system.rate_limit.input_per_sec` (a recommended `__system.*` key, see §10.1) so clients can self-throttle.

Servers MUST bound the size of accepted frames. The default upper bound is 64 KiB. Larger frames MUST trigger an `INVALID_VALUE` error and connection close.

Servers MAY apply additional limits per role : a typical pattern is `viewer = no input allowed` (already enforced by §9), `operator = 60/s`, `service = 600/s`. The default 60/s applies when no per-role limit is documented.

### 14.4 Path injection

Servers MUST validate that every `path` in incoming `input` frames is declared in the active scene's `operator_inputs` (or starts with `__test.` for test sessions). Implicit-creation of paths is forbidden.

### 14.5 Cross-origin

LSDP does not address cross-origin policy. Operators SHOULD configure their WebSocket gateway with appropriate CORS-like restrictions. The Lumencast runtime does not bypass browser same-origin policies.

## 15. Conformance

A server or client is **LSDP/1 conformant** if it passes every `tag: required` scenario in the [conformance suite](../conformance/README.md) for the relevant target (`server`, `runtime`, or `any`).

### 15.1 Conformance profile partition

Scenarios are partitioned into three conformance levels, mapped to RFC 2119 keywords:

| Tag | RFC 2119 mapping | Implementation impact |
|---|---|---|
| `required` | MUST | Failure means the implementation is not LSDP/1-conformant and MUST NOT use the "Lumencast" name without qualification. |
| `recommended` | SHOULD | Failure does not break conformance but the implementation SHOULD document the deviation. |
| `extended` | MAY | Failure is acceptable but discouraged ; corner cases and quality signals. |

Conformance is target-scoped. A `target: server` scenario tests server behaviour ; a `target: runtime` scenario tests client/runtime behaviour ; a `target: any` scenario tests both sides on either role. An implementation claims conformance only for the targets it actually implements.

### 15.2 Test control plane

The conformance suite drives implementations through the **test control plane** specified in [interop/CONTROL.md](../interop/CONTROL.md). LSDP/1 servers that claim conformance MUST expose this control plane (off by default in production, gated by an explicit flag). LSDP/1 runtimes that claim conformance MUST be drivable through it.

The control plane is a normative companion to LSDP/1 ; an implementation that does not expose or honour it cannot be conformance-tested and MUST NOT claim LSDP/1 conformance.

### 15.3 Naming policy

A non-conformant implementation MUST NOT use the "Lumencast" name without qualification (e.g. "Lumencast-derived", "based on Lumencast").

---

## 16. LeafPath grammar

LeafPath is the canonical addressing form for the leaf-grain state map. Every `path` field in `delta.patches`, `input.patches`, and `state` keys in `snapshot` is a LeafPath.

### 16.1 ABNF (RFC 5234)

```abnf
LeafPath     = RegularPath / ScopedPath / ReservedPath
RegularPath  = Identifier *("." Segment)
ScopedPath   = ScopeRef *("." Segment)
ReservedPath = ReservedNs 1*("." ReservedSeg)

Identifier   = ALPHA *(ALPHA / DIGIT / "_")
Segment      = 1*(ALPHA / DIGIT / "_")
ScopeRef     = "{" Identifier "}"
ReservedNs   = "__" 1*LOWER
ReservedSeg  = 1*(ALPHA / DIGIT / "_" / "*" / "-")

LOWER        = %x61-7A             ; a-z
ALPHA        = %x41-5A / %x61-7A   ; A-Z / a-z (RFC 5234 §B.1)
DIGIT        = %x30-39             ; 0-9
```

### 16.2 Equivalent regex

A receiver MAY validate paths with this regex (PCRE-flavoured) :

```
^(?:[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*|\{[A-Za-z_][A-Za-z0-9_]*\}(?:\.[A-Za-z0-9_]+)*|__[a-z]+(?:\.[A-Za-z0-9_*-]+)+)$
```

### 16.3 Constraints

- A LeafPath MUST be 1 to 512 UTF-8 bytes inclusive.
- Each segment MUST be 1 to 64 UTF-8 bytes inclusive.
- Numeric indices in segments are decimal, no leading zeros except for `0` itself, no negative values.
- `ScopeRef` (`{name}`) is valid only inside `repeat` templates ; LSDP frames on the wire MUST NOT contain unresolved scope references.
- `ReservedPath` is restricted to the registered namespaces in §10. Any other `__`-prefixed path is forbidden.

### 16.4 Examples

| Path | Class |
|---|---|
| `score` | RegularPath |
| `players.0.name` | RegularPath |
| `team.alpha.score` | RegularPath |
| `{player}.score` | ScopedPath |
| `{player}.scores.0` | ScopedPath |
| `__inputs.title` | ReservedPath |
| `__system.adapter.scores.healthy` | ReservedPath |
| `__test.session.flag` | ReservedPath |
| `0player` | **invalid** (Identifier must start with letter or `_`) |
| `__custom.foo` | **invalid** (`__custom` is not a registered namespace) |
| `players..0` | **invalid** (empty segment) |

---

## 17. Subscription state machine

The lifecycle of a single subscription on a single WebSocket connection is :

```
                ┌─────────────┐
   open WS  ──▶ │ Connecting  │
                └──────┬──────┘
                       │ WS open
                       ▼
                ┌─────────────┐
  send subscribe│ Subscribing │
                └──────┬──────┘
                       │
            ┌──────────┴──────────┐
            │                     │
            │ recv snapshot       │ recv error(recoverable=false)
            │     (seq=1)         │
            ▼                     ▼
   ┌─────────────┐         ┌──────────────┐
   │    Live     │         │   Closed     │ ─── final
   └──┬─┬─┬─┬─┬──┘         └──────────────┘
      │ │ │ │ │
      │ │ │ │ └─ recv delta / scene_changed → stays Live
      │ │ │ └─── recv error(recoverable=true) → stays Live, surfaced
      │ │ └───── recv scene_changed + new snapshot(seq=1) → stays Live
      │ └─────── seq gap detected → close + reconnect → Reconnecting
      └───────── WS close → Reconnecting (if non-fatal) | Closed (if fatal)

                ┌─────────────┐
                │ Reconnecting│ ─── wait backoff (§7) ─── new WS open ─── back to Connecting
                └─────────────┘
```

### 17.1 State definitions

| State | Description | Permitted incoming frames | Permitted outgoing frames |
|---|---|---|---|
| Connecting | TCP+TLS+WS upgrade in progress | none | none |
| Subscribing | WS open, awaiting first server frame | snapshot, error | (subscribe was sent at entry) |
| Live | Subscription active, normal operation | delta, scene_changed, snapshot (after scene_changed), error, pong | input, ping |
| Reconnecting | Scheduled retry after close | none | none |
| Closed | Terminal | none | none |

### 17.2 State transitions

| From | Trigger | To |
|---|---|---|
| Connecting | WS upgrade success | Subscribing (after sending subscribe) |
| Connecting | WS upgrade failure | Reconnecting |
| Subscribing | recv snapshot(seq=1) | Live |
| Subscribing | recv error(recoverable=false) | Closed |
| Subscribing | recv error(recoverable=true) | Live (with onError surfaced ; subsequent server frames define behaviour) |
| Live | recv delta / pong | Live |
| Live | recv scene_changed + recv snapshot(seq=1) | Live |
| Live | recv error(recoverable=true) | Live (onError) |
| Live | recv error(recoverable=false) | Closed |
| Live | seq gap detected | Reconnecting (close with VERSION_GAP) |
| Live | WS close (network) | Reconnecting |
| Live | dispose() | Closed |
| Reconnecting | backoff elapsed | Connecting |
| Reconnecting | dispose() | Closed |

---

## 18. Incremental resume (1.1+)

Long-lived subscriptions disconnect and reconnect frequently — network blips, mobile transitions, browser tab restoration. Without resume, every reconnect produces a fresh `snapshot` ; the client throws away its cache and re-applies the full state.

LSDP/1.1 lets the client request a **resume from a known sequence point** by including `since_sequence` in its `subscribe` frame (§4.1). When the server's replay buffer covers the gap, it responds with the deltas that occurred between `since_sequence + 1` and the current sequence, instead of a fresh snapshot. The client's cached state remains valid throughout.

### 18.1 Server replay buffer

A 1.1 server MUST maintain a replay buffer per active scene. The buffer SHOULD hold at least the last 256 deltas (or 60 seconds of activity, whichever is more recent). Implementations MAY make this configurable.

When the buffer cannot satisfy a `since_sequence` request (because the requested seq is older than the buffer's earliest entry), the server MUST fall back to a fresh `snapshot(seq=current)` and the client MUST discard its cached state.

A 1.0 server has no buffer and MUST ignore `since_sequence`, replying with a fresh `snapshot` per the original 1.0 contract.

#### 18.1.1 Sequence-number semantics under resume (NORMATIVE)

The `seq` counter is **per-scene, per-active-lifetime** in 1.1 — NOT per-subscription. Specifically :

- Every scene maintains a single monotonic `seq` counter. The first frame ever emitted on the scene is `seq=1`.
- A new subscription receives a `snapshot` whose `seq` is the **current** scene seq (which MAY be `1` if no deltas have been emitted yet, or a much larger number if the scene has been live for hours).
- Subsequent deltas to that subscription continue from that point and increment in lockstep with the scene's global counter.
- All concurrent subscribers see the same `seq` value on a given delta — the value is a property of the *frame*, not of any one connection.
- `scene_changed` resets the counter to 0 (so the next snapshot is `seq=1`). The scene's identity changed ; its history is no longer relevant.

This is the only design that makes incremental resume coherent : a client reconnecting with `since_sequence: N` is asking *"replay from the scene's seq=N+1 forward"*, which only has a well-defined answer if `seq` is global to the scene.

**Migration note for 1.0 → 1.1 servers.** Pre-1.1 implementations frequently used a *per-subscription* counter (every new subscriber's first snapshot was `seq=1`). A 1.0 server upgrading to 1.1 MUST switch to the per-scene model described here. Two consequences :

1. Late-joining subscribers will observe non-1 seq values on their first snapshot. Clients MUST NOT assume snapshot.seq == 1 ; they MUST take the value as authoritative.
2. The 1.0 conformance scenario `subscribe-snapshot-delta` happens to hard-code `seq=1` in its expected snapshot frame because no prior deltas occurred ; this remains valid because the server starts with `seq=0` and increments on each emission. Scenarios that subscribe *after* deltas have flowed MUST use `$ANY` for the snapshot seq.

**1.0 servers** continue to use whatever seq scheme they had before — they don't honour `since_sequence` and their `seq` semantics are out of scope for this spec.

### 18.2 Client expectations

A client requesting resume :

1. Sends `subscribe { token, since_sequence: <last_seen> }`
2. Receives EITHER :
   - A stream of `delta` frames starting at `seq = since_sequence + 1`, in order. The client applies each in turn.
   - A `snapshot { seq: <current> }`. The client throws away its cache and rebases.
3. Continues normally.

If the negotiated subprotocol is `lsdp.v1` (1.0), the client MUST NOT send `since_sequence` — it would be silently dropped, but per §13.2 a client and server agreed on `lsdp.v1` MUST NOT use 1.1 features.

### 18.3 Scene change during disconnect

If the active scene changed while the client was disconnected, the server MUST emit `scene_changed` followed by `snapshot(seq=1)` regardless of the `since_sequence` request. The client cannot resume across a scene boundary — the bundle changed.

### 18.4 Bounded replay

The replay buffer is bounded. Servers MUST NOT honour requests for a `since_sequence` older than what the buffer holds — they fall back to fresh snapshot. This prevents denial-of-service via crafted "I disconnected hours ago" requests : the server's buffer has its own cap, and exceeding it is a fresh-snapshot path with the same cost as a normal reconnect.

---

## Reference

- [Error code taxonomy](ERROR-CODES.md)
- [LSML 1.0 — scene format spec](LSML-1.md)
- [Conformance suite](../conformance/README.md)
- [Architecture overview](../GOVERNANCE.md#architecture)
