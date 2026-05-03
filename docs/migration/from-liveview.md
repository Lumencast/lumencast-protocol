# Migrating from Phoenix LiveView to Lumencast

Phoenix LiveView is the most direct conceptual cousin to Lumencast — both push server-side state to the client and re-render. The difference is **what** travels :

| | Push payload | Client logic | Schema |
|---|---|---|---|
| Phoenix LiveView | HTML diffs | Almost none — DOM is the source of truth | Implicit, defined by your `.heex` template |
| Lumencast (LSDP/1) | Typed state deltas | None — display is closed-primitives only | Explicit, content-addressed JSON (LSML 1.0) |

The migration is worthwhile when : you're not in Elixir, or you want the schema-locked safety LiveView doesn't give, or you want to host the same scene in OBS Browser Source / Pulsar CEF / native kiosks (LiveView is browser-only).

## Mental model translation

| LiveView concept | Lumencast equivalent |
|---|---|
| `mount/3` callback | LSML scene bundle (the layout the runtime fetches) |
| `assigns` map | The state map pushed in `snapshot` + `delta` |
| `handle_event/3` | LSDP `input` frame → server `Authenticator` validates → applies to operator_inputs |
| `push_event/3` | LSDP `delta` frame |
| `Phoenix.PubSub` | Adapter declarations (`external_adapters[]` in LSML) |
| Live navigation | LSDP `scene_changed` frame |
| `~H` template | LSML primitive tree |
| `<.live_component>` | User component (composition of LSML primitives, inlined into the bundle by the authoring tool) |
| Channel auth (`mount/3` on socket) | Lumencast token-agnostic auth — server `Authenticator.authenticate(token)` returns role |

## Side-by-side example

A minimal scoreboard.

### LiveView version

```elixir
defmodule MyAppWeb.ScoreboardLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 1000)
    {:ok, assign(socket, score_home: 0, score_away: 0, title: "Live now")}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1000)
    new_home = socket.assigns.score_home + Enum.random(0..1)
    {:noreply, assign(socket, score_home: new_home)}
  end

  def handle_event("set_title", %{"value" => v}, socket) do
    {:noreply, assign(socket, title: v)}
  end

  def render(assigns) do
    ~H"""
    <div class="scoreboard">
      <h1><%= @title %></h1>
      <div class="scores">
        <span class="home"><%= @score_home %></span>
        <span class="sep">—</span>
        <span class="away"><%= @score_away %></span>
      </div>
    </div>
    """
  end
end
```

### Lumencast version

**Scene bundle (`scoreboard.lsml`)** — authored once :

```json
{
  "lsml": "1.0",
  "scene_id": "scoreboard",
  "scene_version": "sha256:...",
  "layout": {
    "kind": "frame",
    "size": { "w": 1920, "h": 200 },
    "background": "#0f172a",
    "children": [{
      "kind": "stack",
      "direction": "vertical",
      "gap": 16,
      "padding": [16, 16, 16, 16],
      "align": "center",
      "children": [
        {
          "kind": "text",
          "bind": { "value": "__inputs.title" },
          "style": { "fontSize": 32, "color": "#ffffff" },
          "role": "heading"
        },
        {
          "kind": "stack",
          "direction": "horizontal",
          "gap": 24,
          "align": "center",
          "children": [
            { "kind": "text", "bind": { "value": "score.home" }, "format": { "kind": "number" }, "style": { "fontSize": 64, "color": "#fbbf24" } },
            { "kind": "text", "bind": { "value": "literal.dash" }, "style": { "fontSize": 64, "color": "#94a3b8" } },
            { "kind": "text", "bind": { "value": "score.away" }, "format": { "kind": "number" }, "style": { "fontSize": 64, "color": "#fbbf24" } }
          ]
        }
      ]
    }]
  },
  "operator_inputs": [
    {
      "path": "__inputs.title",
      "label": "Title",
      "type": "string",
      "constraints": { "maxLength": 64 },
      "writable_by": ["operator"],
      "default": "Live now"
    }
  ],
  "external_adapters": [
    {
      "kind": "http_poll",
      "interval_ms": 1000,
      "url": "https://api.example.com/scoreboard",
      "writes_to": "score"
    }
  ],
  "defaults": {
    "score.home": 0,
    "score.away": 0,
    "literal.dash": "—"
  }
}
```

**Server (TypeScript with `@lumencast/server`)** :

```ts
import { Server } from "@lumencast/server";
import { readFileSync } from "node:fs";

const bundle = JSON.parse(readFileSync("./scoreboard.lsml", "utf-8"));

const srv = Server.create({
  listen: ":4000",
  bundle,
  authenticator: async (token) => {
    if (token === "operator-secret") return { role: "operator", subject: "op1" };
    if (token === "viewer-secret") return { role: "viewer", subject: "anon" };
    throw new Error("invalid token");
  }
});

const scene = srv.newScene("scoreboard");
scene.set("score.home", 0);
scene.set("score.away", 0);

setInterval(() => {
  scene.emit({ "score.home": scene.get("score.home") + (Math.random() < 0.5 ? 0 : 1) });
}, 1000);

srv.run();
```

(API shape illustrative — match the actual `@lumencast/server` once it ships.)

The HTML template disappears entirely. The runtime renders from the bundle. The operator overlay (control mode) auto-generates a form for `__inputs.title` from the `operator_inputs` declaration — no separate admin page to write.

## What you gain

- **Stack-agnostic** : your server can be Node, Go, Rust, Python, or anything that speaks LSDP/1
- **Multiple host targets** : same scene runs in browser AND OBS Browser Source AND native kiosk
- **Schema-audited** : the scene bundle is JSON-Schema-validated, no template injection surface
- **Bundle versioning** : `scene_version` is a content hash ; rollbacks and canaries are URL changes

## What you lose

- **HEEx convenience** : LiveView's component story (slots, attributes, conditional rendering) is more flexible than LSML's closed primitives. Complex conditional UIs need to be modeled as multiple scenes + `scene_changed`, not as inline conditions.
- **Forms for free** : LiveView's form helpers (`<.form>`, `<.input>`, error handling) don't exist. Operator inputs cover form-style flows but they're declarative, not imperative.
- **`live_redirect`** : Lumencast doesn't navigate URLs. Multi-page apps stay outside Lumencast ; Lumencast handles single-display state streams within a page.

## Common gotchas

- **Don't model nested data as nested JSON in state** — flatten to leaf paths. `players.0.score`, not `players: [{ score }]`. The runtime store is leaf-grained.
- **Don't push HTML in a delta** — values must be string / number / boolean / null / array. Objects are forbidden in `value`. If you have rich content, model the structure as primitives in the bundle.
- **Don't put business logic in the client** — Lumencast is display-only. Compute server-side, push the result.
- **Don't translate `handle_event` into a custom RPC** — Lumencast's `input` frame is the only client-to-server write path, scoped to `operator_inputs`. If you have flows that don't fit, think hard whether they should live outside Lumencast (e.g. a separate REST endpoint).

## Migration steps

1. **Inventory state** : list every `assign(socket, ...)` call. Each becomes a leaf path.
2. **Inventory operator events** : each `handle_event/3` becomes either an `operator_input` (declarative writable field) or moves to a separate REST endpoint (if it's logic, not state).
3. **Translate the template** : map `~H"""..."""` to LSML primitives. `<%= @field %>` becomes `bind: { value: "field" }`.
4. **Identify adapters** : each PubSub subscription, GenServer cast, or DB-backed query becomes an `external_adapters[]` declaration.
5. **Pick a server SDK** : `@lumencast/server` (Node), `lumencast-go`, `lumencast-rs`. Wire the same business logic that drove your LiveView assigns.
6. **Test against conformance** : run `lumencast conformance --target server --server-url <yours>` to verify wire-level correctness.
7. **Replace the LiveView mount** with a Lumencast iframe / embed / Pulsar CEF browser source pointing at the scene URL.

The first three steps are intellectual work. The last four are mechanical.
