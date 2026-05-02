# Migrating from a custom WebSocket + Redux/Zustand to Lumencast

The most common Lumencast migration : you've built a real-time dashboard with a custom WebSocket protocol, a hand-rolled Redux/Zustand store, ad-hoc reconnection logic, and a React tree that re-renders on every state change. It works, but :

- Each new dashboard reinvents the wire protocol
- The wire format is undocumented (or under-documented), making cross-team collaboration hard
- Reconnect is buggy in the long tail (disconnect during a burst, replays, gaps)
- The React store grows over time and "what re-renders when X arrives" becomes opaque

Lumencast doesn't necessarily make your dashboard faster. It makes it **share a wire protocol** with every other dashboard you'll ever build, and replaces 200-1000 lines of bespoke state-management code with `mount()` and a JSON bundle.

## When the migration is the right call

- You operate **multiple dashboards** with different teams (or different products) and protocol drift is a real cost
- You're hitting **reconnection bugs** that would take weeks to debug from scratch (LSDP's sequence-gap detection + bounded backoff is implemented once for everyone)
- You want to **swap the server implementation** without rewriting the client (e.g. moving from a Node monolith to Go microservices)
- You need a **non-React display target** (Vue, Svelte, native, terminal) — sharing the bundle across runtimes is the protocol's raison d'être

## When migration is wrong

- Your custom protocol does something LSDP doesn't (e.g. binary frames for high-throughput numeric streams, custom compression, multi-multiplexed subscriptions on one connection) — LSDP/1 is text-only WebSocket, intentionally
- Your client logic is genuinely **interactive** (drag-and-drop, complex form validation, undo/redo) — Lumencast is display-only
- You're already shipping value and the "shared protocol" pitch isn't load-bearing — premature standardization is worse than no standardization

## Mental model translation

| Custom WS / Redux concept | Lumencast equivalent |
|---|---|
| Custom action types (`SCORE_UPDATED`, `CONNECTION_ADDED`) | LSDP `delta` frame with patches at specific paths |
| Redux reducer | LSML scene + reactive store (the "what does X mean" lives in the bundle's bind paths) |
| `useSelector(state => state.scores.home)` | `bind: { value: "scores.home" }` in LSML, automatic |
| `useDispatch` + `dispatch({type: ...})` | LSDP `input` frame from an operator client |
| Custom WebSocket reconnect logic | LSDP runtime's built-in reconnect schedule |
| Zustand store hooks | Same — automatic via signals, no manual subscription |
| Server-side store | Server SDK's `Scene` with `set()` / `emit()` |
| Local-only UI state (modal open, selected tab, etc.) | NOT migrated — keep this in your existing client store, outside Lumencast's display |

## Side-by-side example

A simple multi-room chat presence dashboard.

### Custom version (TypeScript + Zustand)

```typescript
// client/store.ts
import { create } from "zustand";

interface State {
  rooms: Record<string, { name: string; userCount: number; }>;
  applyEvent: (event: WireEvent) => void;
}

type WireEvent =
  | { type: "ROOM_LIST"; rooms: Array<{ id: string; name: string; userCount: number }> }
  | { type: "USER_JOINED"; roomId: string }
  | { type: "USER_LEFT"; roomId: string };

export const useStore = create<State>((set) => ({
  rooms: {},
  applyEvent: (event) =>
    set((state) => {
      switch (event.type) {
        case "ROOM_LIST":
          return { rooms: Object.fromEntries(event.rooms.map((r) => [r.id, r])) };
        case "USER_JOINED": {
          const room = state.rooms[event.roomId];
          return room ? { rooms: { ...state.rooms, [event.roomId]: { ...room, userCount: room.userCount + 1 } } } : state;
        }
        case "USER_LEFT": {
          const room = state.rooms[event.roomId];
          return room ? { rooms: { ...state.rooms, [event.roomId]: { ...room, userCount: Math.max(0, room.userCount - 1) } } } : state;
        }
      }
    }),
}));
```

```typescript
// client/ws.ts
const ws = new WebSocket(`wss://chat.example.com/presence?token=${token}`);
ws.onopen = () => console.log("open");
ws.onmessage = (e) => useStore.getState().applyEvent(JSON.parse(e.data));
ws.onclose = () => setTimeout(reconnect, 1000); // naive
```

```tsx
// client/App.tsx
function App() {
  const rooms = useStore((s) => s.rooms);
  return (
    <div>
      <h1>Live presence</h1>
      <ul>
        {Object.values(rooms).map((r) => (
          <li key={r.name}>{r.name} — {r.userCount} online</li>
        ))}
      </ul>
    </div>
  );
}
```

### Lumencast version

**Scene bundle** :

```json
{
  "lsml": "1.0",
  "scene_id": "presence",
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
        "bind": { "items": "rooms" },
        "scope": "r",
        "key": "{r}.id",
        "limit": 200,
        "template": {
          "kind": "stack",
          "direction": "horizontal",
          "gap": 16,
          "children": [
            { "kind": "text", "bind": { "value": "{r}.name" }, "style": { "fontSize": 16, "color": "#e5e7eb" } },
            { "kind": "text", "bind": { "value": "{r}.userCount" }, "format": { "kind": "number" }, "style": { "fontSize": 16, "color": "#22c55e" } }
          ]
        }
      }
    ]
  },
  "defaults": { "rooms": [] },
  "i18n": { "default_locale": "en-US", "locales": { "en-US": { "i18n.heading": "Live presence" } } }
}
```

**Server (Go with `lumencast-go`)** :

```go
package main

import (
  "github.com/Lumencast/lumencast-go/server"
  "encoding/json"
  "os"
)

func main() {
  bundleBytes, _ := os.ReadFile("./presence.lsml.json")
  var bundle server.SceneBundle
  json.Unmarshal(bundleBytes, &bundle)

  srv := server.New(server.Config{
    ListenAddr: ":4000",
    Bundle:     bundle,
    Auth:       myAuthenticator,
  })

  scene := srv.NewScene("presence")

  // Subscribe to your existing event source.
  presenceEvents.Subscribe(func(ev PresenceEvent) {
    rooms := scene.Get("rooms").([]any)
    switch ev.Kind {
    case "user_joined":
      // Find room, increment count, emit new array.
      newRooms := updateRoomCount(rooms, ev.RoomID, +1)
      scene.Emit(map[string]any{"rooms": newRooms})
    case "user_left":
      newRooms := updateRoomCount(rooms, ev.RoomID, -1)
      scene.Emit(map[string]any{"rooms": newRooms})
    case "room_list":
      scene.Emit(map[string]any{"rooms": ev.Rooms})
    }
  })

  srv.Run()
}
```

**Client (TypeScript)** :

```tsx
import { mount } from "@lumencast/runtime";

mount({
  target: document.getElementById("presence")!,
  serverUrl: "wss://chat.example.com/presence/stream",
  token: getAuthToken(),
  mode: "broadcast"
});
```

The Zustand store, the action type union, the `applyEvent` switch, the WebSocket reconnect logic, the React component tree — all gone. The runtime handles them, identically across every Lumencast-driven page in your stack.

## What you gain

- **Wire protocol you don't maintain** — LSDP/1 is documented and conformance-tested. Bugs in reconnect / sequencing / replay are fixed once, in the runtime.
- **Server-side replaceability** — your Go server can be swapped for a Rust server with no client changes ; the protocol is the contract.
- **Cross-team consistency** — every dashboard at your company uses the same store-update mental model.
- **Multi-host hosting** — embed the same scene in OBS Browser Source for screen recordings, in a TV wall display, in a mobile webview ; one bundle, three hosts.
- **Schema versioning** — content-hashed bundles let you A/B test new layouts without coordinating client deploys.

## What you lose

- **Custom optimizations** — if your protocol does delta compression, binary blobs, or multiplexing, none of that is in LSDP/1. You either denormalize into multiple paths or keep the optimization outside Lumencast.
- **Imperative state mutation** — Redux's `dispatch(...)` from any component, anywhere, is a client-side affordance. In Lumencast, all writes go through `input` frames to the server. For local-only UI state, keep your existing client store alongside Lumencast.
- **Bespoke retries** — if you have business-specific retry logic (e.g. retry only on `ROOM_RATE_LIMITED`, not on disconnect), you'll need to re-implement it server-side on top of the LSDP-managed connection.

## Common gotchas

- **Mixing local + Lumencast state** : keep local UI state (selected tab, modal open, etc.) in your existing client store. Don't try to push that through Lumencast — it's display-only.
- **Don't normalize via Lumencast** : your Redux store had `state.users.byId[id]` and `state.users.allIds`. Lumencast's leaf-grain protocol means flat paths. If the array is small, push the full array. If the array is large, push just the changed item — Lumencast's `repeat` keying handles the diff efficiently.
- **WebSocket auth** : your custom protocol may have used cookies or query-string tokens. LSDP uses the token in the `subscribe` frame body, so you can't rely on cookies for the WebSocket — token must be available in JavaScript.
- **Server architecture** : if your custom server multiplexed many subscriptions on a single WebSocket, LSDP forbids that (one subscription per connection). Adapt your server to spawn a new connection per scene the operator views.

## Migration steps

1. **Inventory wire events** — list every action type / event your custom protocol emits. Each becomes one or more leaf paths.
2. **Inventory client store paths** — `state.x.y.z` becomes `x.y.z` in Lumencast (with adjustments for arrays). Drop any local-only UI state from this list.
3. **Define the LSML bundle** — translate your React tree to LSML primitives. Keep one bundle per "page" / "scene".
4. **Pick a server SDK** — match your existing server stack (`@lumencast/server` for Node, `lumencast-go` for Go, etc.) and migrate the event-publish points to `scene.emit()`.
5. **Migrate auth** — your token format probably stays. Adapt the WebSocket subscribe to send the token in the LSDP `subscribe` frame.
6. **Wire the client** — replace your custom WebSocket + store + React tree with `mount({ ... })`.
7. **Decommission the old wire format** — once stable, retire the custom protocol code from both ends.

For incremental migration, run both protocols in parallel : the new Lumencast-driven panels and the legacy custom WS panels coexist on the same page until you're confident enough to retire the old.
