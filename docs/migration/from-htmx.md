# Migrating from HTMX + Server-Sent Events to Lumencast

HTMX with SSE is the lightest-weight pattern of server-driven UI : the server emits HTML fragments, the client swaps them into the DOM via attributes like `hx-swap-oob`. It's stack-agnostic, beloved for its simplicity, and the closest in philosophy to "let the server do the rendering." Migrating to Lumencast trades that simplicity for a typed protocol and a hardened runtime — worth it when XSS-safety, multi-host, or schema versioning matter.

| | HTMX + SSE | Lumencast |
|---|---|---|
| Wire format | HTML fragments via SSE | Typed state deltas via WebSocket |
| Client | DOM swaps via attributes | Reactive store + closed primitives |
| Schema | None — server controls every byte of HTML | Explicit JSON Schema, content-addressed |
| XSS surface | Whatever HTML the server emits | None (no eval, no innerHTML) |
| Auth | Whatever your stack does | Token-agnostic, role-aware (viewer/operator/service/test) |

## When the migration is the right call

- **You serve HTML to a Pulsar CEF / OBS Browser Source / native kiosk** — Lumencast's same-bundle-three-hosts story replaces juggling separate templates per target
- **You want the server to be replaceable** — HTMX is stack-agnostic but your HTML strings are not ; Lumencast lets you swap server implementations behind the same protocol
- **You need conformance** — HTMX has no protocol spec ; Lumencast has LSDP/1 + a conformance suite
- **You're hitting XSS or escaping bugs** — Lumencast's closed-primitive catalog makes server-injected HTML literally impossible

## When migration is wrong

- You like HTMX *because* it's "no framework, just HTML" — Lumencast IS more of a framework
- Your client uses HTMX for non-display behaviors (lazy-loading on scroll, click-to-edit, modal dialogs) — those are imperative UI patterns Lumencast doesn't model
- You want your viewer to also be a regular HTML page (search engines, accessibility-via-source) — Lumencast renders DOM via JS, no progressive enhancement

## Mental model translation

| HTMX/SSE concept | Lumencast equivalent |
|---|---|
| `<div hx-ext="sse" sse-connect="/feed">` | Lumencast `mount({ serverUrl: "wss://.../stream", mode: "broadcast" })` |
| `<div sse-swap="message">` (target) | A path in the state tree the server pushes to (e.g. `latest_message`) |
| Server emits `event: message\ndata: <html>` | Server emits LSDP `delta { patches: [{ path, value }] }` |
| `hx-swap-oob="afterbegin:#list"` | Update the array bound to a `repeat` template (prepend new item to head) |
| `hx-trigger="change"` form | An `input` frame from an operator-role connection targeting an `operator_inputs` path |
| HTMX `hx-vals` (custom payload) | Path-scoped writes — the value MUST be a JSON primitive type |
| SSE reconnect | LSDP reconnect with bounded backoff + sequence-gap detection |

## Side-by-side example

A live event log feed.

### HTMX + SSE version

```html
<!-- index.html -->
<div id="feed" hx-ext="sse" sse-connect="/events">
  <h2>Live events</h2>
  <ul id="event-list"></ul>
</div>
```

```python
# server.py (Flask)
from flask import Flask, Response, render_template_string
import time, queue

events = queue.Queue()

@app.route("/events")
def events_stream():
    def generate():
        while True:
            event = events.get()
            html = f'<li hx-swap-oob="afterbegin:#event-list">{event["message"]} ({event["timestamp"]})</li>'
            yield f"event: message\ndata: {html}\n\n"
    return Response(generate(), mimetype="text/event-stream")

# Elsewhere when an event happens:
events.put({"message": "User signed up", "timestamp": "now"})
```

### Lumencast version

**Scene bundle** :

```json
{
  "lsml": "1.0",
  "scene_id": "event-feed",
  "scene_version": "sha256:...",
  "layout": {
    "kind": "stack",
    "direction": "vertical",
    "gap": 8,
    "padding": [16, 16, 16, 16],
    "children": [
      {
        "kind": "text",
        "bind": { "value": "i18n.heading" },
        "style": { "fontSize": 24, "fontWeight": 700, "color": "#ffffff" },
        "role": "heading"
      },
      {
        "kind": "repeat",
        "bind": { "items": "events" },
        "scope": "ev",
        "key": "{ev}.id",
        "limit": 100,
        "template": {
          "kind": "stack",
          "direction": "horizontal",
          "gap": 12,
          "children": [
            { "kind": "text", "bind": { "value": "{ev}.message" }, "style": { "fontSize": 16, "color": "#e5e7eb" } },
            { "kind": "text", "bind": { "value": "{ev}.timestamp" }, "format": { "kind": "relative-time" }, "style": { "fontSize": 12, "color": "#94a3b8" } }
          ]
        }
      }
    ]
  },
  "defaults": { "events": [] },
  "i18n": { "default_locale": "en-US", "locales": { "en-US": { "i18n.heading": "Live events" } } }
}
```

**Server (Python with hypothetical `lumencast-py`)** :

```python
from lumencast import Server, Identity

bundle = json.load(open("./event-feed.lsml"))

def authenticate(token):
    if token == "viewer-secret":
        return Identity(role="viewer", subject="anon")
    raise ValueError("invalid token")

srv = Server(listen=":4000", bundle=bundle, authenticator=authenticate)
scene = srv.new_scene("event-feed")

def on_event(ev):
    current = scene.get("events") or []
    scene.emit({"events": [{"id": ev.id, "message": ev.message, "timestamp": ev.timestamp.isoformat()}] + current[:99]})

# Subscribe `on_event` to your event source (Kafka, Redis pub/sub, internal queue, ...)

srv.run()
```

The HTML stays out of the wire entirely. The runtime renders `<li>` elements (via the `repeat` of stacks) from the typed state. No HTML escaping bugs are possible because the server never builds HTML — only data.

## What you gain

- **Eliminated XSS surface** — even if `event.message` contains `<script>`, the runtime renders it as text inside a `text` primitive. Display-only by construction.
- **Bounded bundle size** — the scene bundle defines max template size ; you can't accidentally explode the DOM with a bad server response.
- **Replay tolerance** — sequence numbers + gap detection. SSE has reconnection but no gap detection ; events received in non-monotonic order silently corrupt state.
- **Offline-ready evolution path** — the protocol's snapshot+delta model is amenable to edge sync extensions (deferred to wave 3).

## What you lose

- **HTML simplicity** — emitting raw HTML strings is fast and flexible. LSML is more strict, more verbose, and updates require a bundle rebuild + version bump.
- **Progressive enhancement** — HTMX gracefully degrades to full-page loads on no-JS clients. Lumencast scenes need a JS runtime ; if SEO or accessibility-via-source is critical, side-load a server-rendered HTML version.
- **Plain-text observability** — SSE is human-readable in `curl`. LSDP frames are JSON, also readable, but harder to "just curl and see what's happening" because they require a WebSocket handshake. Use `lumencast conformance --record` to capture a session for offline analysis.

## Common gotchas

- **Don't try to render arbitrary HTML in a `text` primitive** — `style` props are typography only ; you can't inject markup. If you need bold inline, model it as multiple text primitives in a horizontal stack.
- **List ordering** — HTMX `hx-swap-oob="afterbegin"` mutates DOM in place. Lumencast deltas push the new full array. The runtime's diff-by-key keeps it efficient, but you must provide a stable `key` on the `repeat`.
- **HTMX triggers** like `hx-trigger="every 5s"` push from the client. Lumencast pushes are server-initiated ; set up an adapter (`http_poll` interval_ms: 5000) on the server side.
- **Authentication** — HTMX often inherits the page's session cookie. Lumencast uses a token in the WebSocket `subscribe` frame. Your server's auth layer needs to accept tokens (likely a JWT or opaque bearer).

## Migration steps

1. **Inventory SSE event types** — each `event: <name>` pattern becomes a path or set of paths in state.
2. **Inventory `hx-swap-oob` targets** — each target ID becomes a path. Lists become `repeat` templates with a stable key.
3. **Translate the page template** — outermost div becomes a `frame`, inner regions become nested stacks / grids.
4. **Move HTMX forms** — forms posting to `hx-post` endpoints split into : (a) state mutations → operator_inputs, (b) actions → keep your existing REST endpoints.
5. **Pick a server SDK** — `@lumencast/server`, `lumencast-go`, `lumencast-rs`, `lumencast-py`. Wire your event sources into `scene.emit()`.
6. **Replace** the `hx-ext="sse"` shell with a Lumencast embed (iframe or `<script type="module">` calling `mount()`).

For HTMX apps with mixed display + interactive UI, migrate just the display-driven parts. Keep the form submissions / click handlers / modals on HTMX. The two coexist cleanly when the boundaries are intentional.
