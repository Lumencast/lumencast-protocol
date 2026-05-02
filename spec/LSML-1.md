# LSML 1.0 — Lumencast Scene Markup Language, version 1.0

> **Status** : draft. Will be frozen on first conformance-pass-everywhere release.
>
> **Conformance keyword convention** : the words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, **MAY** are used as defined in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

LSML is the declarative format that describes a Lumencast scene. A *scene bundle* is a JSON document conforming to this spec. The bundle is **content-addressed** — its identity is its sha256 hash — and **immutable** once published.

LSML is what HTML is to HTTP : the format whose instances are transported by the protocol.

---

## Table of contents

1. [Document structure](#1-document-structure)
2. [Versioning](#2-versioning)
3. [Identity & content addressing](#3-identity--content-addressing)
4. [The primitive catalog](#4-the-primitive-catalog)
5. [Bind syntax](#5-bind-syntax)
6. [Animate directives](#6-animate-directives)
7. [Repeat & path scoping](#7-repeat--path-scoping)
8. [Operator inputs](#8-operator-inputs)
9. [External adapters](#9-external-adapters)
10. [Defaults](#10-defaults)
11. [Assets](#11-assets)
12. [Internationalization](#12-internationalization)
13. [Accessibility invariants](#13-accessibility-invariants)
14. [Validation](#14-validation)
15. [Versioning & compatibility](#15-versioning--compatibility)

## 1. Document structure

A scene bundle is a JSON object with the following top-level shape:

```json
{
  "lsml": "1.0",
  "scene_id": "main-stage",
  "scene_version": "sha256:abc123...",
  "layout": { ... },
  "operator_inputs": [ ... ],
  "external_adapters": [ ... ],
  "defaults": { ... },
  "assets": { ... },
  "i18n": { ... },
  "metadata": { ... }
}
```

| Field | Required | Type | Description |
|---|---|---|---|
| `lsml` | yes | string | Schema version. MUST be `"1.0"` for this spec. |
| `scene_id` | yes | string | Stable identifier for the scene. Operator-chosen, not derived. |
| `scene_version` | yes | string | Content hash of the bundle (see §3). |
| `layout` | yes | PrimitiveNode | The root node of the visual tree. |
| `operator_inputs` | optional | array of OperatorInput | Declarative metadata of operator-controllable fields. |
| `external_adapters` | optional | array of AdapterDecl | Server-side adapters that write to specific paths. |
| `defaults` | optional | object | Initial values for leaf paths before any delta. |
| `assets` | optional | object | Asset declarations (URL allowlist, integrity hashes). |
| `i18n` | optional | object | Internationalization tables. |
| `metadata` | optional | object | Authoring metadata (author, description, tags). Not consumed by runtime. |

Receivers MUST ignore unknown top-level fields (forward compatibility).

## 2. Versioning

The `lsml` field declares the schema version this bundle conforms to.

- LSML 1.0 — initial release
- LSML 1.x — backward-compatible additions (new optional fields, new primitives via separate document, new error codes)
- LSML 2.0 — breaking changes

A runtime MUST reject a bundle whose `lsml` major version exceeds its supported maximum, by emitting a `BUNDLE_INCOMPATIBLE` error.

A runtime SHOULD accept any minor version within its supported major (forward compat: ignore unknown optional fields).

## 3. Identity & content addressing

The `scene_version` is the sha256 hash of the **canonicalized** bundle JSON, prefixed with `sha256:`.

Canonicalization rules :

1. UTF-8 encoding
2. Object keys sorted lexicographically at every nesting level
3. No insignificant whitespace (no spaces, tabs, or newlines outside string values)
4. Numbers in shortest decimal form (no exponential, no leading zeros, no trailing zeros after decimal)
5. The `scene_version` field itself is set to `"sha256:0000...0000"` (64 zeros) during hashing, then replaced

Servers serve bundles at URLs that include the version as a query parameter or path segment :

```
https://example.com/static/lumencast/scenes/main-stage/?v=sha256:abc123...
https://example.com/static/lumencast/scenes/main-stage/abc123/
```

Clients MUST verify the `scene_version` matches the hash of the received bundle. Mismatch triggers `BUNDLE_FETCH_FAILED`.

The bundle is **immutable**. Once published, a `scene_version` MUST NOT change. To update a scene, publish a new bundle with a new version.

## 4. The primitive catalog

LSML 1.0 defines exactly **8** primitives. Implementations MUST support all 8. Implementations MUST NOT add custom primitives without bumping LSML major (= LSML 2.0+).

### 4.1 `stack`

A linear container that arranges children along one axis.

```json
{
  "kind": "stack",
  "direction": "horizontal",
  "gap": 12,
  "align": "center",
  "justify": "start",
  "padding": [10, 20, 10, 20],
  "children": [ ... ]
}
```

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `direction` | `"horizontal"` \| `"vertical"` | yes | — | Axis. |
| `gap` | number | no | `0` | Spacing between children, in pixels. |
| `align` | `"start"` \| `"center"` \| `"end"` \| `"stretch"` | no | `"start"` | Cross-axis alignment. |
| `justify` | `"start"` \| `"center"` \| `"end"` \| `"space-between"` \| `"space-around"` | no | `"start"` | Main-axis distribution. |
| `padding` | number \| [top, right, bottom, left] | no | `0` | Inner padding in pixels. |
| `rtl` | `"auto"` \| boolean | no | `"auto"` | RTL layout direction. |
| `children` | array of PrimitiveNode | yes | — | Ordered child nodes. |

### 4.2 `grid`

A 2D grid container.

```json
{
  "kind": "grid",
  "columns": 3,
  "rows": 2,
  "gap": [8, 16],
  "children": [ ... ]
}
```

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `columns` | integer or array of column-spec | yes | — | Number of equal columns, or explicit column tracks. |
| `rows` | integer or array of row-spec | no | auto | Same for rows. |
| `gap` | number \| [row-gap, col-gap] | no | `0` | Spacing. |
| `padding` | number \| array | no | `0` | Inner padding. |
| `children` | array of PrimitiveNode | yes | — | Children placed in row-major order, or per `area` spec. |

A child of `grid` MAY include a `gridArea` field with `[row, column, rowSpan, colSpan]` to position explicitly.

### 4.3 `frame`

An absolutely-positioned container with explicit dimensions. Used as the root of a scene or for overlapping compositions.

```json
{
  "kind": "frame",
  "size": { "w": 1920, "h": 1080 },
  "position": { "x": 0, "y": 0 },
  "background": "#000000",
  "children": [ ... ]
}
```

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `size` | `{ w: number, h: number }` | conditional | — | Required for the root frame. Optional for nested. |
| `position` | `{ x: number, y: number }` | no | `{0,0}` | Position relative to parent. |
| `background` | string (CSS color) | no | transparent | Background fill. |
| `children` | array of PrimitiveNode | yes | — | Children, stacked in z-order. |

### 4.4 `text`

Renders a string of text.

```json
{
  "kind": "text",
  "bind": { "value": "show.title" },
  "style": {
    "fontSize": 48,
    "fontWeight": 700,
    "color": "#ffffff",
    "lineHeight": 1.2,
    "textAlign": "center"
  },
  "format": { "kind": "string" },
  "maxLines": 2
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `bind.value` | LeafPath | yes | Path whose value is rendered. |
| `style` | TextStyle object | no | Typography properties (subset of CSS). |
| `format` | FormatSpec | no | Number/date/currency/relative-time formatter. |
| `maxLines` | integer | no | Truncation with ellipsis after N lines. |

The runtime resolves `bind.value` against the store. If the value is not a string, it is coerced to its JSON string representation **unless** `format` specifies otherwise.

### 4.5 `image`

Renders a raster image.

```json
{
  "kind": "image",
  "bind": { "src": "team.logo.url" },
  "alt": "Team logo",
  "size": { "w": 100, "h": 100 },
  "fit": "contain"
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `bind.src` | LeafPath | yes | Path whose value is the image URL. |
| `alt` | string | yes (a11y) | Accessibility text. MUST be present (see §13). |
| `size` | `{ w, h }` | yes | Rendered size. |
| `fit` | `"contain"` \| `"cover"` \| `"fill"` \| `"none"` | no | Object-fit semantics. Default `"contain"`. |

Image URLs MUST be in the bundle's `assets.allowedHosts` list (§11) or content-hashed. Out-of-allowlist URLs are rejected with `INVALID_VALUE`.

### 4.6 `shape`

Renders a primitive geometric shape via SVG.

```json
{
  "kind": "shape",
  "geometry": "rect",
  "size": { "w": 200, "h": 50 },
  "fill": "#ff0000",
  "stroke": { "color": "#000", "width": 2 },
  "cornerRadius": 8,
  "ariaLabel": "Score bar"
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `geometry` | `"rect"` \| `"circle"` \| `"path"` | yes | Shape kind. |
| `size` | `{ w, h }` | conditional | Required for `rect`/`circle`. |
| `pathData` | string | conditional | Required for `path`, SVG path data syntax. |
| `fill` | CSS color | no | Fill color. |
| `stroke` | `{ color, width }` | no | Stroke. |
| `cornerRadius` | number | no | For `rect` only. |
| `ariaLabel` | string | no | If present, role becomes `img` (informative); else `presentation` (decorative). |

### 4.7 `media`

Renders a video or audio element.

```json
{
  "kind": "media",
  "kind_hint": "video",
  "bind": { "src": "speaker.video_url" },
  "controls": false,
  "autoplay": true,
  "muted": true,
  "loop": false,
  "size": { "w": 640, "h": 360 }
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `kind_hint` | `"video"` \| `"audio"` | yes | Determines element type. |
| `bind.src` | LeafPath | yes | Path whose value is the media URL. |
| `controls` | boolean | no | Show native controls. Default `false` for broadcast. |
| `autoplay` | boolean | no | Default `false`. Most browsers require `muted: true` for autoplay. |
| `muted` | boolean | no | Default `false`. |
| `loop` | boolean | no | Default `false`. |
| `size` | `{ w, h }` | yes (video) | Size for video element. |

### 4.8 `repeat`

Iterates a template over a list, pushing a path scope.

```json
{
  "kind": "repeat",
  "bind": { "items": "players" },
  "scope": "player",
  "key": "{player}.id",
  "template": {
    "kind": "stack",
    "direction": "horizontal",
    "children": [
      { "kind": "text", "bind": { "value": "{player}.name" } },
      { "kind": "text", "bind": { "value": "{player}.score" } }
    ]
  },
  "limit": 10
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `bind.items` | LeafPath | yes | Path whose value is an array (or array-like with numeric index keys). |
| `scope` | string | yes | Identifier introduced into the path-context. |
| `key` | LeafPath template | no | Per-item identity. Defaults to array index. |
| `template` | PrimitiveNode | yes | Subtree rendered per item, with scope substitution. |
| `limit` | integer | no | Max items rendered (truncate). Default unbounded. |

Inside `template`, the scope name in `{...}` is replaced with the path index: `"{player}.name"` becomes `"players.0.name"` for the first item. See §7.

## 5. Bind syntax

Most primitive props that take dynamic values use the `bind` object pattern:

```json
{ "kind": "text", "bind": { "value": "show.title" } }
```

The runtime resolves the bind path against the leaf-grain store. Whenever the path's signal updates, the bound prop updates and the primitive re-renders.

A bind path :
- MUST be a valid LeafPath (dot-separated, alphanumeric + underscore + numeric indices)
- MAY contain scope substitutions in `{name}` form (only inside `repeat` templates)
- MUST refer to a leaf — not a sub-tree

A primitive prop MAY also be bound via `bindStyle` (for nested style props):

```json
{
  "kind": "text",
  "bind": { "value": "score" },
  "bindStyle": { "color": "team.color" }
}
```

Static values are passed directly without `bind`:

```json
{ "kind": "text", "bind": { "value": "score" }, "style": { "fontSize": 48 } }
```

## 6. Animate directives

LSML scenes can declare animations on `transform`, `opacity`, and `filter` properties. **No other property is animatable.**

```json
{
  "kind": "frame",
  "animate": {
    "transition": { "duration": 200, "easing": "spring", "stiffness": 200, "damping": 20 },
    "transform": { "translate": [0, 0], "scale": 1, "rotate": 0 },
    "opacity": 1,
    "filter": { "blur": 0, "brightness": 1 }
  }
}
```

| Prop | Type | Description |
|---|---|---|
| `transition.duration` | number (ms) | For `tween` easing. |
| `transition.easing` | `"linear"` \| `"ease-in"` \| `"ease-out"` \| `"ease-in-out"` \| `"spring"` | Curve. |
| `transition.stiffness` | number | Spring only. |
| `transition.damping` | number | Spring only. |
| `transform.translate` | [x, y] | In pixels. |
| `transform.scale` | number \| [sx, sy] | Uniform or per-axis. |
| `transform.rotate` | number (degrees) | Rotation around center. |
| `opacity` | number (0..1) | |
| `filter.blur` | number (px) | |
| `filter.brightness` | number (0..2) | |

**Why this restriction**: animations on `width`/`height`/`top`/`left` trigger DOM reflow. The runtime's contract is **0 layout events during the animation hot path**. To enforce this, only GPU-composited properties are exposed. A scene that violates this constraint is rejected at validation.

## 7. Repeat & path scoping

When a `repeat` template is rendered, the runtime maintains a path scope that maps `{name}` placeholders to concrete indexed paths.

Given:

```json
{
  "kind": "repeat",
  "bind": { "items": "players" },
  "scope": "player",
  "template": {
    "kind": "text",
    "bind": { "value": "{player}.name" }
  }
}
```

If `players` resolves to `[{name:"Alice"}, {name:"Bob"}]`, the runtime renders two `text` primitives with bind paths `players.0.name` and `players.1.name`.

Nested `repeat` is allowed; each scope must have a unique name within the enclosing scope chain.

The runtime MUST observe the array length via the bound path. When the array shrinks, instances are unmounted; when it grows, instances are mounted.

## 8. Operator inputs

The bundle declares which leaf paths are operator-controllable:

```json
{
  "operator_inputs": [
    {
      "path": "show.title",
      "label": "Show title",
      "type": "string",
      "constraints": { "maxLength": 80 },
      "writable_by": ["operator"],
      "group": "header"
    },
    {
      "path": "show.color_theme",
      "label": "Theme",
      "type": "enum",
      "values": ["dark", "light", "high-contrast"],
      "writable_by": ["operator"]
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `path` | yes | LeafPath under `__inputs.*` namespace. |
| `label` | yes | Human-readable label for the operator UI. |
| `type` | yes | `"string"` \| `"number"` \| `"boolean"` \| `"enum"` \| `"color"` \| `"date"` \| `"time"` \| `"path-ref"` \| `"image-ref"` |
| `constraints` | no | Type-specific constraints (e.g. `maxLength`, `min`, `max`, `pattern`). |
| `writable_by` | yes | Array of roles that can write. Subset of `["operator", "service"]`. |
| `group` | no | Grouping label for operator UI organization. |

Multiple operator UIs (control overlay, Stream Deck, mobile companion) consume this metadata to derive their forms — the bundle is the single source of truth.

## 9. External adapters

The bundle declares server-side adapters that write to specific paths :

```json
{
  "external_adapters": [
    {
      "kind": "http_poll",
      "interval_ms": 200,
      "url": "https://api.example.com/scores",
      "writes_to": "match",
      "auth": { "header": "Authorization", "from_secret": "API_KEY" }
    },
    {
      "kind": "websocket_subscribe",
      "url": "wss://feeds.example.com/orderbook",
      "writes_to": "orderbook"
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `kind` | yes | Adapter type: `http_poll`, `websocket_subscribe`, `pg_listen`, `webhook_receive`, `cron`, etc. |
| `writes_to` | yes | Path prefix the adapter is allowed to write to. Server enforces. |
| (kind-specific fields) | varies | Configuration for the adapter. |

Adapter execution is **server-side**, not runtime-side. The runtime never reads `external_adapters`; it's metadata for the server to act on.

## 10. Defaults

The bundle declares the initial state for paths that may not have a server-emitted value:

```json
{
  "defaults": {
    "show.title": "",
    "show.color_theme": "dark",
    "players": []
  }
}
```

The server seeds the snapshot with these defaults before any adapter or operator input. The runtime treats the snapshot as authoritative — defaults are a bundle-level specification, not a runtime fallback.

## 11. Assets

Asset URLs and integrity policies:

```json
{
  "assets": {
    "allowedHosts": ["cdn.example.com", "static.example.com"],
    "fonts": [
      { "family": "Inter", "url": "https://cdn.example.com/inter.woff2", "sha256": "abc..." }
    ],
    "preload": ["team-logo-1.png", "team-logo-2.png"]
  }
}
```

| Field | Description |
|---|---|
| `allowedHosts` | URL hostnames that `image`/`media` primitives may reference. |
| `fonts` | Web fonts to load before first paint. |
| `preload` | Asset URLs to fetch eagerly. |

A primitive that references an URL outside `allowedHosts` produces an `INVALID_VALUE` error.

## 12. Internationalization

```json
{
  "i18n": {
    "default_locale": "en-US",
    "locales": {
      "en-US": { "show.greeting": "Hello", "score.label": "Score" },
      "fr-FR": { "show.greeting": "Bonjour", "score.label": "Score" },
      "ar-AE": { "show.greeting": "مرحبا", "score.label": "النتيجة" }
    }
  }
}
```

A `text` primitive whose `bind.value` resolves to a path starting with `i18n.` (e.g. `i18n.show.greeting`) is rendered through the locale lookup.

The runtime subscribes to `__inputs.locale` to pick the active locale. Switching locales is a leaf-grain delta — no reload.

## 13. Accessibility invariants

LSML enforces accessibility rules at the schema level:

| Primitive | Rule |
|---|---|
| `image` | `alt` field is REQUIRED. Empty string `""` is allowed for purely decorative images but discouraged. |
| `shape` | If `ariaLabel` set → role `img`. Else role `presentation`. |
| `media` | `aria-label` SHOULD be present. |
| `text` | Role inferred from `style.fontSize` heuristic + parent context, OR explicit `role` field. |

The runtime MUST honour `prefers-reduced-motion`:
- Animations with `transition.duration > 100ms` SHOULD become instantaneous
- Crossfades SHOULD become atomic swaps
- The bundle MAY mark specific animations as essential with `respectsReducedMotion: false` — these are the exception, not the rule.

The runtime MUST honour `prefers-contrast` by lifting the bundle's high-contrast theme variant if declared.

## 14. Validation

A bundle is **valid LSML 1.0** if it passes the JSON Schema published at [schema.json](schema.json).

The CLI :

```sh
lumencast validate scene.json
```

Reports any of:
- Schema violations (wrong field types, missing required fields)
- Animation discipline violations (animating non-allowed props)
- Asset host violations
- Accessibility violations (missing `alt`, etc.)
- Bind path syntax errors

Servers SHOULD validate bundles before serving them. Runtimes SHOULD validate bundles on receipt and emit `BUNDLE_FETCH_FAILED` on validation errors.

## 15. Versioning & compatibility

LSML 1.0 is the initial release. The compatibility policy:

| Change kind | Version bump | Examples |
|---|---|---|
| New optional top-level field | Patch (1.0 → 1.0.1) | New diagnostic metadata field |
| New optional primitive prop | Minor (1.0 → 1.1) | `text.shadow` |
| New primitive | Minor (1.0 → 1.2) | `path` primitive (separate from `shape.path`) |
| Renaming or removing a field | Major (1.x → 2.0) | Renaming `bind.value` to `bind.text` |
| Removing or splitting a primitive | Major | Splitting `media` into `video` + `audio` |

A runtime supporting LSML 1.0 MUST tolerate forward LSML 1.x bundles by ignoring unknown fields.

A runtime MUST reject LSML 2.x bundles with `BUNDLE_INCOMPATIBLE`.

---

## Reference

- [JSON Schema for LSML 1.0](schema.json) (canonical machine-readable spec)
- [LSDP/1 wire protocol](LSDP-1.md) (how bundles travel)
- [Error code taxonomy](ERROR-CODES.md)
- [Conformance suite](../conformance/README.md)
