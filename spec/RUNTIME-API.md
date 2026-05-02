# Runtime API

The canonical surface that every Lumencast runtime exposes, regardless of language or target platform.

> Status: draft. Frozen at the same time as LSDP/1.

The runtime API is the **only** surface a host (browser, native shell, OBS plugin, ...) interacts with. Everything else — transport, state, render, animation, modes — is internal.

## Contract

```typescript
function mount(options: MountOptions): LumencastHandle

interface MountOptions {
  target:    HTMLElement | NativeViewHandle | TerminalScreen;
  serverUrl: string;
  token:     string | TokenProvider;
  mode:      "broadcast" | "control" | "test";
  testSession?: string;
  scene?:       string;
  onStatus?:    (s: Status) => void;
  onError?:     (e: LumencastError) => void;
  onMetric?:    (m: LumencastMetric) => void;
}

interface TokenProvider {
  fetch: () => Promise<string>;
}

interface LumencastHandle {
  setToken(token: string | TokenProvider): void;
  disconnect(): void;
}

type Status = "disconnected" | "connecting" | "live";

interface LumencastError {
  code: ErrorCode;          // see ERROR-CODES.md
  message: string;
  recoverable: boolean;
}

interface LumencastMetric {
  name: "delta_received" | "delta_applied" | "frame_dropped"
      | "reconnect" | "snapshot_received" | "scene_changed";
  // shape varies per metric ; see telemetry section below
  [key: string]: unknown;
}
```

## Lifecycle

```
caller        runtime
  │              │
  │── mount() ──>│   (validates options)
  │              ├─── opens WebSocket to serverUrl
  │              ├─── sends `subscribe` with token
  │              │<── snapshot frame
  │              ├─── fetches scene bundle by scene_version
  │              ├─── seeds store, renders React (or native) tree
  │              ├─── onStatus("live")
  │              │
  │              │<── delta frames apply to store
  │              │    bound primitives re-render
  │              │
  │── setToken ─>│   opens new WS, swaps store atomically
  │              │
  │── disconnect>│   closes WS, unmounts tree, releases store
```

## Idempotence

- Calling `mount()` twice on the same `target` is undefined behavior — the host MUST call `handle.disconnect()` before remounting.
- Calling `disconnect()` after a previous `disconnect()` is a no-op.
- `setToken()` may be called before `live` status is achieved — the runtime queues the token swap to apply when the connection is established.

## Targets per runtime

| Runtime | `target` accepts |
|---|---|
| `@lumencast/runtime` (browser) | `HTMLElement` |
| `lumencast-flutter` | `Widget` slot or `BuildContext` |
| `lumencast-tui` | `Screen` from the runtime's TUI library (e.g. `tcell.Screen`, `bubbletea.Program`) |
| `lumencast-native-cef` | OS-native window handle (`HWND`, `NSWindow`, `wl_surface`) |

The contract is the **shape** of the API. Targets adapt the `target` type to their platform.

## Mode semantics

| Mode | What's rendered | Permitted operations |
|---|---|---|
| `broadcast` | Pure scene, no chrome | `disconnect`, `setToken` |
| `control` | Scene + operator overlay (status pill, control panel) | Plus: `input` frames via the overlay UI (handled internally) |
| `test` | Scene + control + test inspector (mock adapters, state inspector, time controls) | Plus: write to `__test.*` paths via the inspector UI |

A runtime MUST refuse `mount()` with `mode: "test"` if `testSession` is missing or `scene` is missing — both are required. Emit a synchronous error before opening the WebSocket.

## Error surface

All errors flow through `onError(LumencastError)`. The runtime MUST translate :

- LSDP `error` frames → identical `LumencastError` (code, message, recoverable preserved)
- Bundle fetch failures → `LumencastError { code: "BUNDLE_FETCH_FAILED", recoverable: true }`
- Schema mismatch on bundle → `LumencastError { code: "BUNDLE_INCOMPATIBLE", recoverable: false }`
- Sequence gap detected → close + reconnect (NOT surfaced as user-visible error in normal cases)

## Telemetry

`onMetric` is optional. When provided, the runtime emits structured metrics for observability:

```typescript
{ name: "delta_received", count: 1, scene_id: "main-stage", path_count: 5 }
{ name: "delta_applied", duration_ms: 12 }
{ name: "frame_dropped", count: 1, reason: "render-budget-exceeded" }
{ name: "reconnect", attempt: 1, reason_code: "VERSION_GAP" }
{ name: "snapshot_received", state_size_bytes: 1024, scene_id: "main-stage" }
{ name: "scene_changed", from: "main-stage", to: "intermission" }
```

Metric shapes are versioned alongside the runtime API. New metrics may be added in minor versions. Existing metric names MUST NOT change shape without a major bump.

## Conformance

A runtime that honours this contract — same API shape, same error mapping, same telemetry shapes — passes the runtime portion of the conformance suite. The suite drives `mount()`, `setToken()`, `disconnect()` against a known mock-server and verifies behavior matches.
