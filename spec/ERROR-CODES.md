# Error Code Taxonomy

The complete set of error codes that can appear in an LSDP/1 `error` frame. Codes are stable identifiers that runtimes match against — server messages are human-readable but not protocol-normative.

This taxonomy is **closed** for LSDP/1. New codes require a minor version bump (LSDP/1.1, 1.2, ...) following the [RFC process](../GOVERNANCE.md#decision-categories).

## Conventions

- Codes are SCREAMING_SNAKE_CASE
- Codes have a fixed `recoverable` semantics — the same code in different contexts always has the same recoverability
- Servers MUST emit exactly one `code` per `error` frame
- Runtimes MUST match codes by exact string equality

## Authentication & authorization

### `AUTH_DENIED`

The provided token is invalid, expired, or revoked.

- **Recoverable** : `false`
- **Server action** : close the WebSocket
- **Runtime action** : surface to `onError`. Optionally trigger a token refresh and reconnect with `setToken()`.

### `WRITE_FORBIDDEN`

The connection's role does not permit writing the requested path. Sent in response to an `input` frame from a `viewer`, or to an `input` writing outside the role's allowed namespace.

- **Recoverable** : `true` (the connection stays open; only the input is rejected)
- **Server action** : reject the input, do not close
- **Runtime action** : surface to `onError`, do not retry

## Subscription & scene resolution

### `SCENE_NOT_FOUND`

The `scene` field in `subscribe` references a scene that does not exist on the server.

- **Recoverable** : `false`
- **Server action** : close
- **Runtime action** : surface to `onError`, do not auto-retry

### `BUNDLE_FETCH_FAILED`

The runtime cannot retrieve the LSML bundle for the active `scene_version`. May be a 404, network error, or hash mismatch on the fetched bundle.

- **Recoverable** : `true` (runtime can retry)
- **Server action** : N/A — this is a runtime-side error, surfaced via the runtime's `onError`
- **Runtime action** : retry with backoff, or fail-stop after 3 attempts

### `BUNDLE_INCOMPATIBLE`

The LSML bundle declares a major schema version newer than what the runtime supports (e.g. bundle is `lsml: "2.0"` but runtime supports up to 1.x).

- **Recoverable** : `false`
- **Server action** : N/A — runtime-detected
- **Runtime action** : surface to `onError`, runtime cannot continue

## Sequencing

### `VERSION_GAP`

The runtime detected a missing sequence number — server frames are not contiguous. Triggered client-side; the runtime closes and reconnects.

- **Recoverable** : `true` via reconnect
- **Server action** : N/A — client-detected
- **Runtime action** : close with reason `VERSION_GAP`, reconnect

### `VERSION_MISMATCH`

The protocol major version negotiation failed. Server received `subscribe` with `v: 2` but only supports `v: 1` (or vice versa).

- **Recoverable** : `false`
- **Server action** : send error then close
- **Runtime action** : surface to `onError`, do not auto-retry

## Input validation

### `UNKNOWN_PATH`

An `input` frame references a path that is not declared in the active scene's `operator_inputs`.

- **Recoverable** : `true`
- **Server action** : reject the input, do not apply any patch in the frame
- **Runtime action** : surface to `onError` (likely a programming error in the operator UI)

### `INVALID_VALUE`

An `input` value violates the type or constraints declared in the bundle's `operator_inputs` (e.g. a string longer than `maxLength`, a number outside `min`/`max`, an enum value not in the list).

- **Recoverable** : `true`
- **Server action** : reject the input frame entirely (atomic — no patches applied)
- **Runtime action** : surface to `onError`, optionally re-display the previous valid value

## Rate limiting

### `RATE_LIMIT`

The connection has exceeded a server-side rate limit (most commonly `input` frames/second).

- **Recoverable** : `true` (with backoff)
- **Server action** : reject the offending frame, MAY include a `retry_after_ms` field in the message
- **Runtime action** : back off, surface to `onError`. The runtime SHOULD throttle subsequent inputs.

## Test sessions

### `TEST_SESSION_EXPIRED`

The test session has exceeded its TTL (default 5 minutes). The connection is no longer valid.

- **Recoverable** : `false` (a new session must be created)
- **Server action** : close
- **Runtime action** : surface to `onError`, do not auto-retry

## Server health

### `INTERNAL`

A server-side error not covered by a more specific code. Servers SHOULD log details server-side and emit only a sanitized `message` to the client.

- **Recoverable** : varies (server sets `recoverable` per case)
- **Server action** : may close depending on `recoverable`
- **Runtime action** : surface to `onError`, retry per `recoverable`

---

## Adding new codes

Adding a new error code is a minor version bump (LSDP/1.0 → LSDP/1.1) and requires :

1. RFC issue with rationale and examples
2. Discussion (≥ 7 days)
3. Update to this document
4. Update to the conformance suite
5. Implementation in at least one reference SDK before merge

Codes MUST NOT be removed or renamed without a major version bump.

## Mapping to runtime callbacks

Each code surfaces to the runtime's `onError(LumencastError)` callback with shape :

```typescript
interface LumencastError {
  code: ErrorCode;        // exact string match against this taxonomy
  message: string;        // server-provided, English
  recoverable: boolean;   // server-provided, fixed per code
}
```

Runtimes MUST NOT introduce client-only error codes that mimic server codes. If a runtime needs to surface a client-side error (e.g. `BUNDLE_FETCH_FAILED`), it uses the same code with `recoverable: true` and a clear `message`.
