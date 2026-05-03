# Error Code Taxonomy

The complete set of error codes that can appear in an LSDP/1 `error` frame, plus the client-detected codes runtimes surface through the same callback shape.

Codes are stable identifiers that runtimes match against — server messages are human-readable but not protocol-normative.

This taxonomy is **closed** for LSDP/1. New codes require a minor version bump (LSDP/1.1, 1.2, ...) following the [RFC process](../GOVERNANCE.md#decision-categories).

## Conventions

- Codes are SCREAMING_SNAKE_CASE
- Codes have a fixed `recoverable` semantics — the same code in different contexts always has the same recoverability
- Servers MUST emit exactly one `code` per `error` frame
- Runtimes MUST match codes by exact string equality
- Some codes carry **per-code extra fields** beyond the base envelope. The complete set is closed per code (see [LSDP-1.md §3.4.1](LSDP-1.md#341-per-code-extra-fields)).

This taxonomy partitions codes into two groups :

- **Server-emitted** : the server detected the condition and emitted an `error` frame on the wire (§ 1 below).
- **Client-detected** : the runtime detected the condition locally and surfaces it through `onError` using the same code shape (§ 2 below). Client-detected codes never appear on the wire.

---

## 1. Server-emitted codes

### 1.1 Authentication & authorization

### `AUTH_DENIED`

The provided token is invalid, expired, or revoked.

- **Recoverable** : `false`
- **Server action** : close the WebSocket
- **Runtime action** : surface to `onError`. Optionally trigger a token refresh and reconnect with `setToken()`.

### `WRITE_FORBIDDEN`

The connection's role does not permit writing the requested path. Sent in response to an `input` frame from a `viewer`, or to an `input` writing outside the role's allowed namespace.

- **Recoverable** : `true` (the connection stays open; only the input is rejected)
- **Extra fields** : `path` (REQUIRED — the rejected target path)
- **Server action** : reject the input, do not close
- **Runtime action** : surface to `onError`, do not retry

### 1.2 Subscription & scene resolution

### `SCENE_NOT_FOUND`

The `scene` field in `subscribe` references a scene that does not exist on the server.

- **Recoverable** : `false`
- **Server action** : close
- **Runtime action** : surface to `onError`, do not auto-retry

### `BUNDLE_INCOMPATIBLE` (server-emitted variant)

The server received a subscribe whose negotiated bundle major version exceeds what the server can serve. (The runtime-detected variant is in §2.)

- **Recoverable** : `false`
- **Extra fields** : `requested_version`, `supported_version` (both optional)
- **Server action** : send error then close
- **Runtime action** : surface to `onError`, runtime cannot continue

### 1.3 Sequencing

### `VERSION_MISMATCH`

The protocol major version negotiation failed. Server received `subscribe` with `v: 2` but only supports `v: 1` (or vice versa).

- **Recoverable** : `false`
- **Server action** : send error then close (WS code 1002)
- **Runtime action** : surface to `onError`, do not auto-retry

### 1.4 Input validation

### `UNKNOWN_PATH`

An `input` frame references a path that is not declared in the active scene's `operator_inputs`.

- **Recoverable** : `true`
- **Extra fields** : `path` (REQUIRED — the undeclared path)
- **Server action** : reject the input, do not apply any patch in the frame
- **Runtime action** : surface to `onError` (likely a programming error in the operator UI)

### `INVALID_VALUE`

An `input` value violates the type or constraints declared in the bundle's `operator_inputs` (e.g. a string longer than `maxLength`, a number outside `min`/`max`, an enum value not in the list).

- **Recoverable** : `true`
- **Extra fields** : `path` (REQUIRED — the path whose value violated its constraint)
- **Server action** : reject the input frame entirely (atomic — no patches applied)
- **Runtime action** : surface to `onError`, optionally re-display the previous valid value

### 1.5 Rate limiting

### `RATE_LIMIT`

The connection has exceeded a server-side rate limit (most commonly `input` frames/second — see [LSDP-1.md §14.3](LSDP-1.md#143-backpressure--dos)).

- **Recoverable** : `true` (with backoff)
- **Extra fields** : `retry_after_ms` (optional — earliest retry time)
- **Server action** : reject the offending frame, MAY include `retry_after_ms`
- **Runtime action** : back off, surface to `onError`. The runtime SHOULD throttle subsequent inputs.

### 1.6 Test sessions

### `TEST_SESSION_EXPIRED`

The test session has exceeded its TTL (default 5 minutes). The connection is no longer valid.

- **Recoverable** : `false` (a new session must be created)
- **Extra fields** : `session` (optional — the session UUID that expired)
- **Server action** : close
- **Runtime action** : surface to `onError`, do not auto-retry

### 1.7 Server health

### `INTERNAL`

A server-side error not covered by a more specific code. Servers SHOULD log details server-side and emit only a sanitized `message` to the client.

- **Recoverable** : varies (server sets `recoverable` per case)
- **Server action** : may close depending on `recoverable`
- **Runtime action** : surface to `onError`, retry per `recoverable`

---

## 2. Client-detected codes

These codes are surfaced by the runtime through the same callback shape as server-emitted codes, but they are NEVER sent on the wire. Server implementations MUST NOT emit them.

### `BUNDLE_FETCH_FAILED`

The runtime cannot retrieve the LSML bundle for the active `scene_version`. May be a 404, network error, or hash mismatch on the fetched bundle.

- **Recoverable** : `true` (runtime can retry)
- **Origin** : runtime-side
- **Runtime action** : retry with backoff, or fail-stop after 3 attempts. Surface to `onError`.

### `BUNDLE_INCOMPATIBLE` (runtime-detected variant)

The LSML bundle declares a major schema version newer than what the runtime supports (e.g. bundle is `lsml: "2.0"` but runtime supports up to 1.x), OR the layout tree contains a primitive `kind` the runtime does not recognise.

- **Recoverable** : `false`
- **Origin** : runtime-side
- **Runtime action** : surface to `onError`, runtime cannot continue. Closes the connection per LSML 1.0 §15.

### `VERSION_GAP`

The runtime detected a missing sequence number — server frames are not contiguous. The runtime closes the WebSocket with this reason and reconnects.

- **Recoverable** : `true` via reconnect
- **Origin** : runtime-side
- **Runtime action** : close with reason `VERSION_GAP`, reconnect, surface to `onError`.

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

Each code surfaces to the runtime's `onError(...)` callback with the following JSON shape (language-neutral) :

```json
{
  "code": "WRITE_FORBIDDEN",
  "message": "viewer role cannot write __inputs.title",
  "recoverable": true,
  "path": "__inputs.title"
}
```

JSON Schema fragment :

```json
{
  "type": "object",
  "required": ["code", "message", "recoverable"],
  "properties": {
    "code": { "type": "string" },
    "message": { "type": "string", "minLength": 1 },
    "recoverable": { "type": "boolean" },
    "path": { "type": "string" },
    "retry_after_ms": { "type": "integer", "minimum": 0 },
    "requested_version": { "type": "string" },
    "supported_version": { "type": "string" },
    "session": { "type": "string" }
  },
  "additionalProperties": false
}
```

The full frame schema lives at [spec/schema-frames.json](schema-frames.json) §`ErrorFrame`.

Runtimes MUST NOT introduce client-only error codes outside the closed taxonomy. The codes in §2 are the only sanctioned client-detected codes.
