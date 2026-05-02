# Migration cookbooks

Concrete side-by-side guides for moving an existing system to Lumencast. Each cookbook covers :

- The mental model translation
- Common shapes you have today
- The Lumencast equivalent
- Gotchas and patterns that don't translate

## Available cookbooks

| Source | Cookbook |
|---|---|
| Phoenix LiveView | [`from-liveview.md`](from-liveview.md) |
| Hotwire / Turbo Streams | [`from-hotwire.md`](from-hotwire.md) |
| HTMX + Server-Sent Events | [`from-htmx.md`](from-htmx.md) |
| Custom WebSocket + Redux | [`from-custom-ws.md`](from-custom-ws.md) |

## When migration is wrong

Lumencast is not a drop-in replacement for any of these tools. **Don't migrate** if :

- You need bidirectional collaborative state with conflict resolution → use Liveblocks, Yjs, or Replicache
- Your client has rich business logic (form workflows, multi-step wizards, user preferences) → Lumencast's display-only contract is too restrictive
- Your server is already shipping HTML and you're happy with that → Hotwire / LiveView are mature, no migration ROI
- You need offline-first with eventual consistency → Lumencast is online-first, edge sync is a deferred extension

Lumencast wins when the pattern is genuinely "server pushes state to a passive display". That's narrower than "real-time UI" in general.

## Migration scope checklist

For any migration, expect to do :

- [ ] Identify the **state shape** : everything the display reads
- [ ] Flatten state to leaf paths (e.g. `user.profile.name` → `user.profile.name`, not nested objects)
- [ ] Define the **scene bundle** : the LSML JSON describing the layout
- [ ] List **operator inputs** : the writable subset of state with constraints
- [ ] Define **adapters** : where the server pulls state from (HTTP polls, queues, DBs)
- [ ] Map your **auth tokens** to Lumencast roles (viewer / operator / service)
- [ ] Decide which **render mode** the host uses (broadcast / control / test)

The cookbooks below walk through each migration with concrete code on both sides.

## How long does it take

A simple display (one panel, ≤10 paths, no animations) — half a day per developer.

A complex broadcast scene (multiple panels, repeat blocks, animations, multi-locale) — 1-2 weeks including the new authoring flow + integration testing.

A full operator console with custom forms — Lumencast probably isn't the right fit. Reach out via GitHub Discussions before committing.
