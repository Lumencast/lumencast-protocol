# LSML 1.0 — Lumencast Scene Markup Language, version 1.0

> **Status** : 1.0.1 (errata + completeness). Backward-compatible with 1.0 ; tightens grammar / constraint vocabulary / canonicalisation reference, adopts JCS (RFC 8785), closes the adapter `kind` list, resolves `i18n` notation collision, formalises validation coverage and forward-compat fallback for unknown primitives.
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

### 3.1 Canonical form

LSML 1.0 uses **JSON Canonicalization Scheme (JCS)** as defined by [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) for the canonical form of every bundle, with one explicit divergence (see §3.2).

JCS in summary :

1. UTF-8 encoding (no BOM)
2. Object keys sorted lexicographically by their UTF-16 code-unit value at every nesting level
3. No insignificant whitespace (no spaces, tabs, or newlines outside string values)
4. Numbers serialised per ECMAScript `Number.prototype.toString` (RFC 8785 §3.2.2) — shortest round-trippable decimal form, no leading zeros, no trailing zeros after decimal, no exponential notation for integers in the safe range
5. Unicode strings escaped per RFC 8785 §3.2.1

### 3.2 Divergence — `scene_version` placeholder

JCS hashes the entire JSON document. LSML's `scene_version` is itself a field of the document, which would create a chicken-and-egg : the hash depends on a value that depends on the hash.

LSML 1.0 resolves this with a placeholder protocol :

1. Set `scene_version` to the literal string `"sha256:0000000000000000000000000000000000000000000000000000000000000000"` (64 zeros) before canonicalisation
2. Canonicalise the bundle per §3.1
3. Compute sha256 of the canonical bytes
4. Set `scene_version` to `"sha256:" + lower-hex(hash)` for the published bundle

Verifiers reverse the process : on receipt, replace the bundle's `scene_version` with the placeholder, recanonicalise, recompute the hash, and check it matches what was claimed.

This divergence is the only deviation from RFC 8785. All other rules apply unchanged.

### 3.3 Distribution

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
  "media_kind": "video",
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
| `media_kind` | `"video"` \| `"audio"` | yes | Determines element type. |
| `bind.src` | LeafPath | yes | Path whose value is the media URL. |
| `controls` | boolean | no | Show native controls. Default `false` (broadcast/overlay use case is the primary target). |
| `autoplay` | boolean | no | Default `false`. Most browsers require `muted: true` for autoplay. |
| `muted` | boolean | no | Default `false`. |
| `loop` | boolean | no | Default `false`. |
| `size` | `{ w, h }` | yes (when `media_kind` is `"video"`) | Size for video element. Audio MAY omit. |

**Deprecation notice** : LSML 1.0 originally named this field `kind_hint`. As of 1.0.1, `media_kind` is the canonical name. Validators MUST accept `kind_hint` as a synonym for backward compatibility, but new bundles SHOULD use `media_kind`. The synonym will be removed in LSML 2.0.

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

Most primitive props that take dynamic values use the `bind` object pattern. Static values are passed directly on the prop ; dynamic values are passed through `bind`.

### 5.1 `bind` object

```json
{ "kind": "text", "bind": { "value": "show.title" } }
```

`bind` is a JSON object whose keys are **prop names** declared by the primitive (`value` for `text`, `src` for `image` and `media`, `items` for `repeat`, etc.), and whose values are **LeafPaths**.

Formal shape :

```
bind         = { propName: LeafPath, ... }
propName     = identifier matching ^[a-zA-Z_][a-zA-Z0-9_]*$
LeafPath     = per LSDP-1.md §16
```

Constraints :

- Each `propName` MUST be one of the bindable props declared by the primitive's spec (§4.x). A `propName` not declared as bindable for the primitive is a validation error.
- The LeafPath MAY contain scope substitutions in `{name}` form, but only inside a `repeat` template (§7).
- The LeafPath MUST refer to a leaf — never a sub-tree. Binding a primitive prop to an object-typed value is undefined behaviour.

The runtime resolves each LeafPath against the leaf-grain store. Whenever the path's signal updates, the bound prop updates and the primitive re-renders.

### 5.2 `bindStyle` object

For style props (typography, layout, color), a primitive MAY use `bindStyle` to bind individual style sub-properties to LeafPaths :

```json
{
  "kind": "text",
  "bind": { "value": "score" },
  "bindStyle": { "color": "team.color", "fontSize": "ui.size" }
}
```

Formal shape :

```
bindStyle    = { styleProp: LeafPath, ... }
styleProp    = identifier matching ^[a-zA-Z_][a-zA-Z0-9_]*$
```

Constraints :

- Each `styleProp` MUST be a key the primitive's `style` object accepts (§4.x).
- Same LeafPath rules as `bind`.
- A primitive MAY combine `style` (static) and `bindStyle` (dynamic) ; if a key appears in both, `bindStyle` wins at runtime.

### 5.3 Mixing static and bound props

Static and bound values can be mixed freely. Static values omit `bind` entirely :

```json
{
  "kind": "text",
  "bind": { "value": "score" },
  "style": { "fontSize": 48, "color": "#ffffff" },
  "bindStyle": { "color": "team.color" }
}
```

In this example, `value` is dynamic, `fontSize` is static, and `color` is dynamic (overriding the static `#ffffff`).

## 6. Animate directives

LSML scenes declare target values for `transform`, `opacity`, and `filter` properties. The runtime interpolates from the current rendered state toward the declared targets according to a transition specification. **No other property is animatable.**

### 6.1 Shape

```json
{
  "kind": "frame",
  "animate": {
    "transition": { "duration": 200, "easing": "spring", "stiffness": 200, "damping": 20, "mass": 1 },
    "transform": { "translate": [0, 0], "scale": 1, "rotate": 0 },
    "opacity": 1,
    "filter": { "blur": 0, "brightness": 1 }
  }
}
```

| Prop | Type | Description |
|---|---|---|
| `transition.easing` | `"linear"` \| `"ease-in"` \| `"ease-out"` \| `"ease-in-out"` \| `"spring"` | Curve. |
| `transition.duration` | number (ms) | Required for tween easings (`linear` / `ease-*`). Forbidden for `spring`. |
| `transition.stiffness` | number | Spring only. Default `170`. |
| `transition.damping` | number | Spring only. Default `26`. |
| `transition.mass` | number | Spring only. Default `1`. |
| `transform.translate` | [x, y] (numbers, px) | In pixels. |
| `transform.scale` | number \| [sx, sy] | Uniform or per-axis. |
| `transform.rotate` | number (degrees) | Rotation around the primitive's centre. |
| `opacity` | number (0..1) | Compositing alpha. |
| `filter.blur` | number (px ≥ 0) | Maps to CSS [`filter: blur(<value>px)`](https://www.w3.org/TR/filter-effects-1/#funcdef-filter-blur). |
| `filter.brightness` | number (≥ 0) | Maps to CSS [`filter: brightness(<value>)`](https://www.w3.org/TR/filter-effects-1/#funcdef-filter-brightness) — `0` is fully dark, `1` is unchanged, `2` is doubled luminance. The runtime MAY clamp to a sane upper bound (e.g. `4`) for performance. |

### 6.2 Spring physics

When `easing: "spring"`, the interpolation follows the **damped harmonic oscillator** model :

```
m · ẍ + c · ẋ + k · (x - target) = 0
```

with parameters :

- `m` = `transition.mass` (kg, default `1`)
- `c` = `transition.damping` (kg/s, default `26`)
- `k` = `transition.stiffness` (kg/s², default `170`)
- `x` = current rendered value, `target` = declared `animate` value

The runtime integrates this ODE per frame using semi-implicit Euler with the frame-Δt as the timestep. Initial conditions when the target changes : current `x` and current `ẋ` (velocity carries through to avoid snap when retargeting mid-animation).

The spring "completes" when `|x - target| < ε` and `|ẋ| < ε` for some implementation-defined ε (typically `0.01` for translates in pixels, `0.001` for unitless scalars).

Runtimes MAY pre-compute spring trajectories for short, low-stiffness configurations to avoid per-frame ODE integration ; the result MUST be visually indistinguishable.

### 6.3 Triggering

Animations are **value-change driven**. A primitive's `animate` block declares the target state for each animatable property. The runtime tracks the rendered state and animates toward the declared targets whenever the targets change.

Concretely :

1. On primitive mount, the rendered state initialises from the declared `animate` targets (instant, no interpolation — there's no previous state).
2. If `animate` contains `bind`-style references (animation targets bound to leaf paths), then **changes to the bound paths trigger interpolation** from the previous rendered state toward the new target.
3. If `animate` contains only static targets, animation runs only on (re)mount or on `scene_changed` crossfade.

Targets MAY be bound via `bindAnimate` (analogous to `bind` / `bindStyle` from §5) :

```json
{
  "kind": "frame",
  "animate": { "opacity": 0, "transform": { "translate": [0, 0] } },
  "bindAnimate": {
    "opacity": "ui.panel.opacity",
    "transform.translate": "ui.panel.position"
  }
}
```

`bindAnimate` keys MUST reference animatable properties only (the §6.1 list). The LeafPath value MUST resolve to a value whose JSON shape matches the property type (e.g. `[x, y]` for `transform.translate`).

### 6.4 Why this restriction

Animations on `width` / `height` / `top` / `left` trigger DOM reflow. The runtime's contract is **0 layout events during the animation hot path**. To enforce this, only GPU-composited properties are exposed. A scene that violates this constraint is rejected at validation with `BUNDLE_INCOMPATIBLE`.

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

Nested `repeat` is allowed. Each scope MUST have a unique name within the enclosing scope chain — a `repeat` whose `scope` shadows an outer scope name is a validation error (`SCOPE_NAME_COLLISION`). Validators MUST reject such bundles before serving.

Example of valid nesting :

```json
{
  "kind": "repeat",
  "bind": { "items": "teams" },
  "scope": "team",
  "template": {
    "kind": "repeat",
    "bind": { "items": "{team}.players" },
    "scope": "player",
    "template": {
      "kind": "text",
      "bind": { "value": "{player}.name" }
    }
  }
}
```

Reusing `team` as the inner scope is forbidden ; the validator MUST reject it.

The runtime MUST observe the array length via the bound path. When the array shrinks, instances are unmounted; when it grows, instances are mounted.

## 8. Operator inputs

The bundle declares which leaf paths are operator-controllable :

```json
{
  "operator_inputs": [
    {
      "path": "__inputs.show_title",
      "label": "Show title",
      "type": "string",
      "constraints": { "maxLength": 80 },
      "writable_by": ["operator"],
      "group": "header"
    },
    {
      "path": "__inputs.show_color_theme",
      "label": "Theme",
      "type": "enum",
      "constraints": { "values": ["dark", "light", "high-contrast"] },
      "writable_by": ["operator"]
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `path` | yes | LeafPath under the `__inputs.*` reserved namespace (LSDP/1.0 §10). The bundle MUST declare paths in their full `__inputs.<segment>...` form ; implicit-prefix conventions are not supported. |
| `label` | yes | Human-readable label for the operator UI. |
| `type` | yes | `"string"` \| `"number"` \| `"boolean"` \| `"enum"` \| `"color"` \| `"date"` \| `"time"` \| `"path-ref"` \| `"image-ref"` |
| `constraints` | no | Type-specific constraints. The complete vocabulary is defined in §8.1 below. |
| `writable_by` | yes | Array of roles that can write. Subset of `["operator", "service"]`. |
| `group` | no | Grouping label for operator UI organization. |

Multiple operator UIs (control overlay, Stream Deck, mobile companion) consume this metadata to derive their forms — the bundle is the single source of truth.

### 8.1 Constraint vocabulary

The `constraints` object MUST contain only keys from the closed list below, scoped to the declared `type`. Unknown constraint keys are a validation error.

| `type` | Constraint key | Type | Semantics |
|---|---|---|---|
| `"string"` | `maxLength` | integer ≥ 0 | Maximum character count (chars, not bytes). |
| `"string"` | `minLength` | integer ≥ 0 | Minimum character count. |
| `"string"` | `pattern` | string (RFC 5234 PCRE) | Regex the value MUST match. |
| `"number"` | `min` | number | Inclusive minimum. |
| `"number"` | `max` | number | Inclusive maximum. |
| `"number"` | `step` | number > 0 | Quantisation step ; the value MUST be an integer multiple of `step` from `min`. |
| `"enum"` | `values` | array of string, non-empty | Allowed values (closed set). |
| `"color"` | (no constraints) | — | Always a CSS color string (#hex / rgb() / rgba() / hsl() / hsla() / named). |
| `"boolean"` | (no constraints) | — | — |
| `"date"` | `min` | string (ISO 8601 date) | Earliest allowed date inclusive. |
| `"date"` | `max` | string (ISO 8601 date) | Latest allowed date inclusive. |
| `"time"` | `min` | string (ISO 8601 time) | Earliest allowed time inclusive. |
| `"time"` | `max` | string (ISO 8601 time) | Latest allowed time inclusive. |
| `"path-ref"` | (no constraints) | — | Value MUST be a valid LeafPath. |
| `"image-ref"` | (no constraints) | — | Value MUST be a URL allowed by `assets.allowedHosts` (§11). |

Servers MUST enforce the constraints on every `input` frame ; violations trigger `INVALID_VALUE` (LSDP/1.0 §3.4, §3.4.1).

### 8.2 Constraint precedence

`constraints` always takes precedence over the implicit type bounds (e.g. JSON number range). When multiple constraints apply, ALL MUST be satisfied — there's no implicit OR.

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
| `kind` | yes | Adapter type from the closed list in §9.1. |
| `writes_to` | yes | LeafPath prefix the adapter is allowed to write to. Server MUST enforce — patches outside the prefix are dropped + logged. |
| (kind-specific fields) | varies | Configuration per `kind` ; see `spec/adapters/<kind>.json` for the schema. |

Adapter execution is **server-side**, not runtime-side. The runtime never reads `external_adapters` ; it's metadata for the server to act on.

### 9.1 Closed `kind` list for LSML 1.0

LSML 1.0 defines exactly **5** adapter kinds. Implementations MAY support a subset (servers indicate supported kinds via the test control plane health endpoint or vendor-specific discovery). Servers receiving an unsupported `kind` MUST surface it through their administrative logs and SHOULD reject scene loads that depend on it ; runtimes never see this — adapters are server-internal.

| `kind` | Schema | Description |
|---|---|---|
| `http_poll` | [`spec/adapters/http_poll.json`](adapters/http_poll.json) | Periodic HTTP/HTTPS GET against `url`, JSON response merged into `writes_to`. |
| `websocket_subscribe` | [`spec/adapters/websocket_subscribe.json`](adapters/websocket_subscribe.json) | Long-lived WebSocket subscription, frames merged into `writes_to`. |
| `pg_listen` | [`spec/adapters/pg_listen.json`](adapters/pg_listen.json) | PostgreSQL `LISTEN`/`NOTIFY` channel, payloads merged into `writes_to`. |
| `webhook_receive` | [`spec/adapters/webhook_receive.json`](adapters/webhook_receive.json) | Inbound HTTP endpoint that the server hosts ; POST bodies merged into `writes_to`. |
| `cron` | [`spec/adapters/cron.json`](adapters/cron.json) | Scheduled trigger that emits a fixed payload at the cron schedule. |

Adding a new adapter kind is a minor LSML version bump (1.0 → 1.1) following the [RFC process](../GOVERNANCE.md#decision-categories). Vendors MAY ship custom adapters off-spec, but bundles using them are not LSML-conformant and MUST NOT use the "Lumencast" name.

### 9.2 Auth and secrets

Adapter configurations MAY reference secrets via `from_secret: "<NAME>"`. The server resolves `<NAME>` against its secret store (env var, vault, etc.). Bundles MUST NOT contain literal credentials in their JSON.

## 10. Defaults

The bundle declares the initial state for paths that may not have a server-emitted value :

```json
{
  "defaults": {
    "__inputs.show_title": "",
    "__inputs.show_color_theme": "dark",
    "players": []
  }
}
```

The server seeds the snapshot with these defaults before any adapter or operator input. The runtime treats the snapshot as authoritative — defaults are a bundle-level specification, not a runtime fallback.

### 10.1 Precedence

When a path appears both in `defaults` and as an `operator_inputs` declaration, the `defaults` value wins as the seed value. Subsequent `input` frames overwrite it through the normal write path. There is no separate "default value" per `operator_input` — declare it in `defaults`.

When a path appears both in `defaults` and as an `external_adapters` write target, the `defaults` value is the seed at scene load ; the adapter overwrites on its first emission. Servers MUST start adapters AFTER seeding defaults.

## 11. Assets

Asset URLs and integrity policies :

```json
{
  "assets": {
    "allowedHosts": ["cdn.example.com", "*.static.example.com"],
    "fonts": [
      { "family": "Inter", "url": "https://cdn.example.com/inter.woff2", "sha256": "abc..." }
    ],
    "preload": ["team-logo-1.png", "team-logo-2.png"]
  }
}
```

| Field | Description |
|---|---|
| `allowedHosts` | Hostname patterns that `image` / `media` primitives MAY reference. Matching rules in §11.1 below. |
| `fonts` | Web fonts to load before first paint. |
| `preload` | Asset URLs to fetch eagerly. |

A primitive that references a URL whose hostname is not allowed produces an `INVALID_VALUE` error.

### 11.1 `allowedHosts` matching

Each entry is matched against the URL's hostname (`URL.host` per WHATWG URL §4.3.2) using one of three patterns :

| Pattern | Match |
|---|---|
| Exact hostname (e.g. `cdn.example.com`) | URL hostname MUST equal the entry exactly (case-insensitive). |
| Wildcard prefix (e.g. `*.example.com`) | URL hostname MUST end with `.example.com` AND have at least one preceding label. `*.example.com` matches `cdn.example.com` but NOT `example.com` itself. |
| IP literal (e.g. `192.0.2.1`, `[::1]`) | URL hostname MUST equal the entry exactly. No wildcard expansion. |

`allowedHosts` does NOT constrain the URL path or port. Operators that need stricter URL allowlisting SHOULD enforce it at the proxy layer ; LSML's responsibility ends at hostname.

### 11.2 Font integrity

Fonts MAY include a `sha256` field for subresource integrity (`integrity="sha256-..."` on the loaded `<link>`). The runtime MUST verify the hash before installing the font ; mismatch raises `INVALID_VALUE` and the font is not used (a fallback font from the platform is rendered instead).

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

The keys inside each locale map are **i18n keys**, not LeafPaths. They live in their own namespace, distinct from the leaf-state addressing space.

### 12.1 Referencing i18n keys

A `text` primitive references an i18n key via the `i18n` prop, NOT through `bind` :

```json
{ "kind": "text", "i18n": "show.greeting" }
```

`i18n: "<key>"` instructs the runtime to render the localised string for the active locale, falling back to `default_locale` if the key is missing in the active locale.

`i18n` is mutually exclusive with `bind.value` on a `text` primitive — declaring both is a validation error.

LSML 1.0 originally suggested binding to a `i18n.<key>` path inside the leaf-state ; this conflicted with the LeafPath grammar and was ambiguous for keys with dots in them. The `i18n` prop is the canonical and only-supported form as of 1.0.1.

### 12.2 Active locale

The runtime subscribes to `__inputs.locale` to pick the active locale. Switching locales is a leaf-grain delta — no reload, no re-fetch. The `__inputs.locale` value MUST be one of the keys in `i18n.locales`.

## 13. Accessibility invariants

LSML enforces accessibility rules at the schema level:

| Primitive | Rule |
|---|---|
| `image` | `alt` field is REQUIRED. Empty string `""` is allowed for purely decorative images but discouraged. |
| `shape` | If `ariaLabel` set → role `img`. Else role `presentation`. |
| `media` | `aria-label` SHOULD be present. |
| `text` | Role inferred from `style.fontSize` heuristic + parent context, OR explicit `role` field. |

The runtime MUST honour `prefers-reduced-motion` per [WCAG 2.1 SC 2.3.3 (Animation from Interactions, Level AAA)](https://www.w3.org/WAI/WCAG21/Understanding/animation-from-interactions.html) :

- Animations with `transition.duration > 100ms` SHOULD become instantaneous (the 100 ms threshold mirrors the WCAG guidance that motion below this duration is unlikely to trigger vestibular reactions).
- Spring-driven animations SHOULD become instantaneous regardless of stiffness when `prefers-reduced-motion: reduce` is set.
- Crossfades SHOULD become atomic swaps.
- The bundle MAY mark specific animations as essential with `respectsReducedMotion: false` — these are the exception, not the rule, and SHOULD be reserved for animations that carry information the user cannot infer otherwise (e.g. live data ticking).

The runtime MUST honour `prefers-contrast` by lifting the bundle's high-contrast theme variant if declared.

## 14. Validation

A bundle is **valid LSML 1.0** if it passes BOTH the JSON Schema in §14.1 AND the contextual rules in §14.2. Schema-only validation is necessary but not sufficient.

### 14.1 Schema-level checks

[`spec/schema.json`](schema.json) (JSON Schema draft 2020-12) covers :

- Top-level shape (required fields : `lsml`, `scene_id`, `scene_version`, `layout`)
- Per-primitive shape (`stack` / `grid` / `frame` / `text` / `image` / `shape` / `media` / `repeat`)
- LeafPath grammar (LSDP-1.md §16, mirrored here)
- Operator-input shape (path / label / type / constraints / writable_by / group)
- External-adapter shape with `kind` enumeration (§9.1)
- Animation property restrictions (§6.4)
- Asset structure
- i18n structure

A bundle that fails schema validation is rejected with `INVALID_VALUE` (or `BUNDLE_INCOMPATIBLE` if the failure is structural enough that the runtime cannot meaningfully recover).

### 14.2 Contextual checks (validator-only)

Some rules cannot be expressed as JSON Schema and require a separate validator pass :

| Check | Rule |
|---|---|
| `operator_inputs.path` namespace | Each `path` MUST start with `__inputs.` (§8). |
| `bind` path target | The bound LeafPath MUST be referenced by a `defaults` entry, an `external_adapters.writes_to` prefix, an `operator_inputs.path` declaration, OR be a path the layout's `repeat` scope produces. Dangling binds are validation errors. |
| `bindStyle` keys | Each key MUST be an attribute of the primitive's `style` object (§5.2). |
| `repeat` scope uniqueness | Nested scopes MUST have unique names within the chain (§7). |
| Asset host references | Every URL referenced by `image` / `media` / `media_kind: "video"` `bind.src` MUST resolve to a host in `assets.allowedHosts` (§11.1). The validator can only check bundle-static URLs ; URLs that come from `bind` are validated at runtime. |
| `text.alt` accessibility | Required on `image` ; checked even when `bind`-driven. |
| Animation discipline | Properties under `animate` and `bindAnimate` MUST be in the §6.1 list. |

The CLI bundles both passes :

```sh
lumencast validate scene.json
```

The CLI exit code is non-zero on any failure.

### 14.3 Validator deployment

Servers SHOULD validate bundles before serving them. Runtimes SHOULD validate bundles on receipt and emit `BUNDLE_INCOMPATIBLE` on structural validation errors (unknown primitives, schema-breaking shape) or surface non-fatal `INVALID_VALUE` events for runtime-validated URL allowlist violations.

A scene authored against a stricter validator (e.g. a future LSML 1.1 with extra optional checks) MUST remain valid against a 1.0 validator — backward compat is forward-only restricted (§15).

## 15. Versioning & compatibility

LSML 1.0 is the initial release. The compatibility policy:

| Change kind | Version bump | Examples |
|---|---|---|
| New optional top-level field | Patch (1.0 → 1.0.1) | New diagnostic metadata field |
| New optional primitive prop | Minor (1.0 → 1.1) | `text.shadow` |
| New primitive | Minor (1.0 → 1.2) | `path` primitive (separate from `shape.path`) |
| Renaming or removing a field | Major (1.x → 2.0) | Renaming `bind.value` to `bind.text` |
| Removing or splitting a primitive | Major | Splitting `media` into `video` + `audio` |

A runtime supporting LSML 1.0 MUST tolerate forward LSML 1.x bundles by ignoring unknown OPTIONAL fields. Specifically :

- Unknown top-level optional fields → ignore silently
- Unknown optional props on a known primitive → ignore silently
- Unknown optional props on an `operator_input` → ignore silently
- Unknown optional fields on an `external_adapter` of a known `kind` → ignore silently

### 15.1 Unknown primitive `kind`

Forward compat does NOT extend to unknown primitive `kind` values in the layout tree. If LSML 1.1 introduces a new primitive `chart` and a 1.0 runtime receives a bundle whose layout contains `{"kind": "chart", ...}`, the runtime MUST :

1. Stop processing the bundle
2. Surface `BUNDLE_INCOMPATIBLE` (with `recoverable: false`) — see [ERROR-CODES.md §2](ERROR-CODES.md#2-client-detected-codes)
3. Disconnect from the LSDP/1 connection

This is intentional : a 1.0 runtime cannot meaningfully render a tree containing an unknown primitive (its layout slot is not omittable), and rendering a partial tree would mislead the operator about what's on screen.

### 15.2 Unknown adapter `kind`

By contrast, unknown `external_adapters.kind` values do not produce client-detectable errors — adapters are server-internal. Servers receiving an unsupported `kind` SHOULD log a warning and either decline to serve the scene OR serve it with the affected paths empty. The bundle remains valid LSML, just incompletely supported on that server.

### 15.3 Major version mismatch

A runtime MUST reject LSML 2.x bundles with `BUNDLE_INCOMPATIBLE`.

---

## Reference

- [JSON Schema for LSML 1.0](schema.json) (canonical machine-readable spec)
- [LSDP/1 wire protocol](LSDP-1.md) (how bundles travel)
- [Error code taxonomy](ERROR-CODES.md)
- [Conformance suite](../conformance/README.md)
