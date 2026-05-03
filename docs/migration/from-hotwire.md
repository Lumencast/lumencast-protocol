# Migrating from Hotwire / Turbo Streams to Lumencast

Hotwire (Turbo Frames + Turbo Streams) pushes HTML fragments from a Rails server to update specific DOM regions. Lumencast pushes typed state and the client renders from a schema. The migration is similar in spirit — server-driven UI updates — but the wire format and client model differ.

| | Hotwire | Lumencast |
|---|---|---|
| Wire format | HTML fragments + action verbs (`append`, `replace`, `prepend`, ...) | Leaf-grain typed state deltas |
| Client model | DOM is the source of truth | Reactive store with one signal per path |
| Schema | Implicit (your ERB template) | Explicit, content-addressed (LSML 1.0) |
| Stack | Locked to Rails (Turbo Streams broadcast via Action Cable) | Stack-agnostic |

## Mental model translation

| Hotwire concept | Lumencast equivalent |
|---|---|
| `<turbo-frame id="x">` | A `frame` primitive with an addressable scope (typically a `repeat` slot) |
| `<turbo-stream action="replace" target="x">` + new HTML | LSDP `delta` frame with patches at the path that backs that region |
| `Turbo::StreamsChannel.broadcast_replace_to(...)` | Server emits a `delta` to all subscribers via `(*Scene).Emit(...)` |
| Action Cable channel + Pubsub | Adapter declarations (`external_adapters[]`) for server-side data sources |
| `<%= @user.name %>` in ERB | `{ "kind": "text", "bind": { "value": "user.name" } }` in LSML |
| Form-driven action with `data-turbo-stream` | `input` frame from a privileged client (operator role) targeting a specific `operator_inputs` path |
| `turbo_frame_request?` | `mode === "control"` runtime mode |

## Side-by-side example

A live notifications panel.

### Hotwire version

```erb
<%# views/notifications/index.html.erb %>
<turbo-frame id="notifications">
  <ul class="notifications">
    <% @notifications.each do |notif| %>
      <li id="notif_<%= notif.id %>"><%= notif.message %></li>
    <% end %>
  </ul>
</turbo-frame>
```

```ruby
# controllers/notifications_controller.rb
def create
  @notif = Notification.create!(user: current_user, message: params[:message])
  Turbo::StreamsChannel.broadcast_append_to(
    "user_#{current_user.id}_notifications",
    target: "notifications",
    partial: "notifications/notification",
    locals: { notif: @notif }
  )
  head :ok
end
```

```ruby
# models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
end
```

### Lumencast version

**Scene bundle** :

```json
{
  "lsml": "1.0",
  "scene_id": "notifications",
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
        "style": { "fontSize": 18, "fontWeight": 700, "color": "#ffffff" },
        "role": "heading"
      },
      {
        "kind": "repeat",
        "bind": { "items": "notifications" },
        "scope": "n",
        "key": "{n}.id",
        "limit": 50,
        "template": {
          "kind": "stack",
          "direction": "horizontal",
          "gap": 12,
          "align": "center",
          "children": [
            { "kind": "text", "bind": { "value": "{n}.message" }, "style": { "fontSize": 14, "color": "#e5e7eb" }, "maxLines": 2 },
            { "kind": "text", "bind": { "value": "{n}.timestamp" }, "format": { "kind": "relative-time" }, "style": { "fontSize": 12, "color": "#94a3b8" } }
          ]
        }
      }
    ]
  },
  "defaults": {
    "notifications": []
  },
  "i18n": {
    "default_locale": "en-US",
    "locales": { "en-US": { "i18n.heading": "Notifications" } }
  }
}
```

**Server (Ruby with hypothetical `lumencast-rb`)** :

```ruby
require "lumencast"

bundle = JSON.parse(File.read("./notifications.lsml"))
server = Lumencast::Server.new(
  listen: ":4000",
  bundle: bundle,
  authenticator: ->(token) {
    user = User.find_by(api_token: token)
    user.nil? ? nil : { role: :viewer, subject: user.id }
  }
)

# When a notification is created, push a delta to the user's scene.
NotificationCreated.subscribe do |notif|
  scene = server.scene_for(notif.user.id)
  current = scene.get("notifications") || []
  scene.emit({
    "notifications" => [{ "id" => notif.id, "message" => notif.message, "timestamp" => notif.created_at.iso8601 }] + current
  })
end

server.run
```

(API shape illustrative — `lumencast-rb` is a wave-3 community SDK.)

## What you gain

- **Wire-level efficiency** : updating one notification means pushing one item, not re-rendering a partial. For a 50-item list updated 10 times/sec, the bandwidth difference is significant.
- **Multi-host** : a Hotwire stream is browser-only. A Lumencast scene runs in OBS Browser Source, native kiosks, mobile webviews, etc.
- **No Action Cable lock-in** : Lumencast doesn't require Rails / Action Cable / Redis as the broadcast backend. Any stack speaking LSDP works.

## What you lose

- **Rails ergonomics** : `link_to`, form helpers, Stimulus controllers — Lumencast doesn't replace these. Side-load Stimulus for any imperative-UI behavior that doesn't fit the display contract.
- **Server-side templating velocity** : adding a new partial is fast in Hotwire. In Lumencast you update the bundle (which is a versioned artifact). Plan releases accordingly.
- **Free progressive enhancement** : Hotwire works on no-JS browsers via Turbo Drive's full-page navigation fallback. Lumencast requires a JS runtime (the LSML scene is bootstrapped by `mount()`).

## Common gotchas

- **Don't push pre-rendered HTML through a Lumencast delta** — the value field forbids objects, and HTML strings would defeat the schema-locked safety. Render in the LSML primitive tree.
- **`turbo-frame` IDs were navigation anchors** — Lumencast doesn't navigate. Multi-page flows stay in your Rails router ; each "page" with a Lumencast component embeds its own scene.
- **Hotwire's `prepend` / `append` actions don't have a direct LSDP equivalent** — you push the **new full state** of the list. The runtime's reactive store handles the diffing efficiently as long as you key the `repeat` template properly.
- **Stream subscriptions per-user** were free in Action Cable. In Lumencast, the equivalent is one Lumencast subscription per user, where the server filters which deltas each connection sees based on the auth identity.

## Migration steps

1. **Inventory turbo-stream broadcasts** : every `Turbo::StreamsChannel.broadcast_*_to` call becomes a `Scene.emit` call on the server side.
2. **Inventory turbo-frame regions** : each addressable region becomes a path or sub-tree in the LSML layout. Lists become `repeat` blocks.
3. **Translate ERB partials to LSML primitives** : the HTML structure maps to nested stacks / grids / frames.
4. **Move forms** : forms with `data-turbo-stream` become `operator_inputs` declarations (for editable state) or stay as separate REST endpoints (for actions).
5. **Side-load Stimulus** for any client-side imperative behavior that doesn't fit display-only.
6. **Replace** the `<turbo-frame>` shell on the page with a Lumencast iframe or `<webview>` pointing at the scene URL.

For larger Rails apps, migrate one panel at a time. Hotwire and Lumencast can coexist on the same page indefinitely — a Lumencast iframe inside a Rails page is a clean isolation.
