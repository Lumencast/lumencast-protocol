# LSDP/1 — Leaf State Delta Protocol, version 1

> **Status** : draft. Will be frozen on first conformance-pass-everywhere release.
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

## 1. Transport

LSDP/1 runs over **WebSocket** (RFC 6455) only. Other transports (HTTP/3, QUIC, raw TCP) are out of scope for v1.

The WebSocket subprotocol negotiation MUST set the `Sec-WebSocket-Protocol` header to `lsdp.v1`. Servers MUST reject upgrade requests that do not advertise this subprotocol with HTTP 426.

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
| `ts` | string (ISO 8601) | optional | Server-generated timestamp for diagnostics. SHOULD be sent on snapshots and errors; MAY be omitted on deltas for bandwidth. |

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
    { "path": "players.0.score", "value": 7 },
    { "path": "show.title", "value": "Match Point" }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `patches` | yes | Non-empty array of `{path, value}` patches. Order matters: applied left-to-right. |

A single `delta` frame is atomic from the runtime's perspective — all patches MUST be applied before the runtime renders the next frame.

`value` MUST be one of: JSON string, number, boolean, null, or array. Objects are forbidden in `value` — if you need to update a nested structure, push leaf-grain patches.

### 3.3 `scene_changed`

The active scene has been swapped server-side. The runtime MUST refetch the bundle at `scene_version`, seed a new store, render a new tree, and crossfade. The runtime MUST receive a new `snapshot` frame after this — sequence resets to 1.

```json
{
  "v": 1,
  "type": "scene_changed",
  "seq": 100,
  "scene_id": "intermission",
  "scene_version": "sha256:def456..."
}
```

After a `scene_changed`, the next server frame MUST be a `snapshot` for the new scene with `seq = 1`. Any `delta` between the `scene_changed` and the `snapshot` is undefined behavior — receivers SHOULD discard.

### 3.4 `error`

A recoverable or fatal error condition. After an `error` frame, the server MAY close the connection. The runtime SHOULD propagate the error to its `onError` callback.

```json
{
  "v": 1,
  "type": "error",
  "seq": 50,
  "code": "WRITE_FORBIDDEN",
  "message": "viewer role cannot send input frames",
  "recoverable": false
}
```

| Field | Required | Description |
|---|---|---|
| `code` | yes | Error code from the closed taxonomy (see [ERROR-CODES.md](ERROR-CODES.md)) |
| `message` | yes | Human-readable description, English |
| `recoverable` | yes | Boolean. `true` if the runtime can attempt to continue (e.g. retry with a fresh token), `false` if the runtime should disconnect. |

### 3.5 `pong`

Heartbeat reply. See §12.

```json
{ "v": 1, "type": "pong" }
```

## 4. Frames — client to server

### 4.1 `subscribe`

Sent immediately after WebSocket open. Identifies the client and the subscription target.

```json
{
  "v": 1,
  "type": "subscribe",
  "token": "<auth-token>",
  "scene": "main-stage",
  "session": null
}
```

| Field | Required | Description |
|---|---|---|
| `token` | yes | Opaque authentication token. Server validates and assigns role. |
| `scene` | conditional | Required for **test mode** (subscribe to a specific scene under preview). Forbidden for **live mode** (server picks the active scene). |
| `session` | conditional | Required for **test mode** with isolated session, forbidden otherwise. |

Server MUST respond with either `snapshot` (success) or `error` (failure).

### 4.2 `input`

Mutate operator inputs. Allowed only for clients with `operator` or `service` role. Forbidden for `viewer` role.

```json
{
  "v": 1,
  "type": "input",
  "patches": [
    { "path": "__inputs.show_title", "value": "New title" },
    { "path": "__inputs.show_visible", "value": true }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `patches` | yes | Non-empty array of `{path, value}` patches |

Server MUST validate each patch against the active scene's `operator_inputs` declaration:

- Unknown path → `error { code: UNKNOWN_PATH }`, MUST NOT apply any patch
- Type mismatch → `error { code: INVALID_VALUE }`, MUST NOT apply any patch
- Path not in `__inputs.*` namespace and not in `__test.*` (for test sessions) → `error { code: WRITE_FORBIDDEN }`

Successful inputs are reflected back to **all** subscribers as a `delta` (the client that sent the `input` will see its own change applied via `delta`).

### 4.3 `ping`

Heartbeat. See §12.

```json
{ "v": 1, "type": "ping" }
```

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
3. Atomically replace the active connection's store with the new snapshot's state
4. Close the old WebSocket

This produces zero rendering interruption for the user.

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

LSDP reserves four leaf-path namespaces:

| Namespace | Purpose | Writable by |
|---|---|---|
| `__inputs.*` | Operator inputs (declared in LSML `operator_inputs`) | `operator`, `service` |
| `__system.*` | Server-emitted system state (e.g. adapter health) | server only |
| `__test.*` | Test session sandbox | `test` only, in test sessions |
| `__schema.*` | Reserved for future use (introspection) | undefined in LSDP/1 |

Any path starting with `__` and not in this list is **reserved** and SHOULD NOT be used. Future LSDP versions may add namespaces here.

User-defined paths MUST NOT start with `__`.

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

The `v: 1` envelope field is the **major**. Minor versions are not signaled in the envelope; they are inferred from server behavior. A client compatible with LSDP/1.0 MUST be forward-compatible with LSDP/1.x.

A client that receives a frame type it does not recognize MUST ignore it silently (forward compat).

A server that receives a `subscribe` from a `v: 2` client while only supporting `v: 1` MUST close the WebSocket with code 1002 (Protocol Error).

## 14. Security considerations

### 14.1 Token confidentiality

The `token` is sent in plaintext inside the WebSocket frame. WebSocket connections MUST be `wss://` (TLS). Plaintext `ws://` is allowed only on localhost for development and MUST NOT be used in production.

### 14.2 Replay protection

LSDP does not provide replay protection at the protocol level. Tokens SHOULD have short expiration (≤ 1 hour) or single-use semantics where appropriate. Servers MAY also bind tokens to client IPs.

### 14.3 Backpressure & DoS

Servers SHOULD rate-limit `input` frames per connection. A reasonable default is 60 inputs/second. Exceeding triggers `RATE_LIMIT` error.

Servers SHOULD bound the size of accepted frames (default 64 KiB). Larger frames trigger an `INVALID_VALUE` error and connection close.

### 14.4 Path injection

Servers MUST validate that every `path` in incoming `input` frames is declared in the active scene's `operator_inputs` (or starts with `__test.` for test sessions). Implicit-creation of paths is forbidden.

### 14.5 Cross-origin

LSDP does not address cross-origin policy. Operators SHOULD configure their WebSocket gateway with appropriate CORS-like restrictions. The Lumencast runtime does not bypass browser same-origin policies.

## 15. Conformance

A server or client is **LSDP/1 conformant** if it passes the [conformance suite](../conformance/README.md) for LSDP/1.

The conformance suite includes:

- Envelope encoding round-trip
- Each frame type's shape validation
- Sequence number monotonicity
- Gap detection and reconnect
- Scene_changed → snapshot reset
- Error code taxonomy
- Role-based write authorization
- Token rotation
- Heartbeat

A non-conformant implementation MUST NOT use the "Lumencast" name without qualification (e.g. "Lumencast-derived", "based on Lumencast").

---

## Reference

- [Error code taxonomy](ERROR-CODES.md)
- [LSML 1.0 — scene format spec](LSML-1.md)
- [Conformance suite](../conformance/README.md)
- [Architecture overview](../GOVERNANCE.md#architecture)
