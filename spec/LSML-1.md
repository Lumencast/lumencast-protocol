# LSML 1.1 — Lumencast Scene Markup Language, version 1.1

> **Status** : 1.1 — additive over 1.0.1. Adds the `instance` primitive (composite-instance reuse), universal props (`visible`, `sizing`, `opacity`, `rotation`) on every primitive, multi-fill + linear/radial gradients on `shape` and `frame.background`, stack `wrap` + `crossGap`, animation engine extensions (color interpolation in sRGB, keyframe sequences, stagger), and §17 Extension Mechanisms (vendor-prefixed primitives + adapters, `profiles[]`, `metadata` escape hatch). Every addition is optional ; 1.0 receivers ignore them. Bundles declare `lsml: "1.1"` to opt into the new features, or keep `"1.0"` for backward-compat targets.
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
16. (reserved)
17. [Extension mechanisms (1.1+)](#17-extension-mechanisms-11)
18. [On-disk format](#18-on-disk-format)

## 1. Document structure

A scene bundle is a JSON object with the following top-level shape:

```json
{
  "$schema": "https://lumencast.dev/schema/lsml/1.1/schema.json",
  "lsml": "1.1",
  "scene_id": "main-stage",
  "scene_version": "sha256:abc123...",
  "layout": { ... },
  "operator_inputs": [ ... ],
  "external_adapters": [ ... ],
  "defaults": { ... },
  "assets": { ... },
  "i18n": { ... },
  "metadata": { ... },
  "profiles": [ ... ]
}
```

| Field | Required | Type | Description |
|---|---|---|---|
| `$schema` | optional | string | Recommended for on-disk bundles. URL of the JSON Schema this bundle conforms to. Enables auto-validation and autocomplete in JSON-Schema-aware editors. Ignored by runtimes (informational only). See §18. |
| `lsml` | yes | string | Schema version. `"1.0"` (and the 1.0.1 errata-compat alias) or `"1.1"`. |
| `scene_id` | yes | string | Stable identifier for the scene. Operator-chosen, not derived. |
| `scene_version` | yes | string | Content hash of the bundle (see §3). |
| `layout` | yes | PrimitiveNode | The root node of the visual tree. |
| `operator_inputs` | optional | array of OperatorInput | Declarative metadata of operator-controllable fields. |
| `external_adapters` | optional | array of AdapterDecl | Server-side adapters that write to specific paths. |
| `defaults` | optional | object | Initial values for leaf paths before any delta. |
| `assets` | optional | object | Asset declarations (URL allowlist, integrity hashes). |
| `i18n` | optional | object | Internationalization tables. |
| `metadata` | optional | object | Authoring metadata (author, description, tags). Not consumed by runtime. |
| `profiles` | optional | array of string | (1.1+) Capability profiles required for correct rendering (§17.3). |

Receivers MUST ignore unknown top-level fields (forward compatibility).

## 2. Versioning

The `lsml` field declares the schema version this bundle conforms to.

- LSML 1.0 — initial release
- LSML 1.0.1 — errata + completeness (no semantic change)
- LSML 1.1 — first additive feature release : `instance` primitive, universal props (`visible`, `sizing`, `opacity`, `rotation`), multi-fill / gradients on `shape` and `frame.background`, stack `wrap` + `crossGap`, animation engine extensions (color interpolation, keyframes, stagger), extension mechanisms (§17)
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
| `gap` | number | no | `0` | Spacing between children along the main axis, in pixels. |
| `crossGap` | number | no | `0` | (1.1+) Spacing between rows/columns when `wrap: true`. Ignored when `wrap` is `false`. |
| `wrap` | boolean | no | `false` | (1.1+) Enable cross-axis wrap (CSS `flex-wrap: wrap`). Children that overflow the main axis flow onto the next row/column. |
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

```json
{
  "kind": "frame",
  "size": { "w": 1920, "h": 1080 },
  "backgrounds": [
    { "kind": "linear-gradient", "angle_deg": 180, "stops": [
        { "offset": 0, "color": "#1a1a2e" },
        { "offset": 1, "color": "#000000" }
    ]}
  ],
  "children": [ ... ]
}
```

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `size` | `{ w: number, h: number }` | conditional | — | Required for the root frame. Optional for nested. |
| `position` | `{ x: number, y: number }` | no | `{0,0}` | Position relative to parent. Universal prop in 1.1+ (see §5.4) ; the duplicate row here is kept for back-compat with 1.0/1.1.0 frame definitions. |
| `clipsContent` | boolean | no | `true` | (1.1+) When `true` (default), children outside the frame's `size` are clipped. When `false`, children may render past the frame boundary ; the frame does not auto-grow. |
| `background` | string (CSS color) | no | transparent | Single solid background fill. Mutually exclusive with `backgrounds`. |
| `backgrounds` | array of [Fill](#412-fill-spec) | no | — | (1.1+) Stacked backgrounds, top-to-bottom (the first entry renders on top). Mutually exclusive with `background`. Supports solid colors, linear gradients, radial gradients. |
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

#### 4.4.1 Round-tripping case-transformed text from authoring tools (1.1+)

Figma's `textCase`, Sketch's `textTransform`, and CSS `text-transform` all describe the same concept : the literal `characters` are stored as authored, and the renderer applies the case transform at paint time. LSML's `TextStyle.textTransform` (already in 1.1) is the canonical home for this.

Authoring tools SHOULD map their native case-transform field to `style.textTransform` :

| Source | LSML `style.textTransform` |
|---|---|
| Figma `UPPER`, Sketch `uppercase`, CSS `uppercase` | `"uppercase"` |
| Figma `LOWER`, Sketch `lowercase`, CSS `lowercase` | `"lowercase"` |
| Figma `TITLE`, Sketch `capitalize`, CSS `capitalize` | `"capitalize"` |
| Figma `ORIGINAL`, CSS `none` | omit the field |
| Figma `SMALL_CAPS`, `SMALL_CAPS_FORCED` | not representable — keep in `metadata.<vendor>` until the spec adds an enum value |

Authoring tools MUST NOT pre-transform the literal `characters` (e.g. uppercase the string at export) because that loses the information needed for case-aware locales (Turkish dotted/dotless `i`, German `ß` ↔ `SS`). Tools SHOULD NOT use `metadata.*` for the standard three cases — that makes the bundle non-portable across runtimes that already honour `textTransform`.

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

```json
{
  "kind": "shape",
  "geometry": "rect",
  "size": { "w": 200, "h": 50 },
  "fills": [
    { "kind": "linear-gradient", "angle_deg": 90, "stops": [
        { "offset": 0, "color": "#ff7e00" },
        { "offset": 1, "color": "#ff1a3d" }
    ]},
    { "kind": "solid", "color": "#00000033" }
  ],
  "strokes": [
    { "color": "#ffffff", "width": 1 }
  ],
  "cornerRadius": 8
}
```

```json
{
  "kind": "shape",
  "geometry": "path",
  "size": { "w": 120, "h": 80 },
  "paths": [
    { "data": "M0,0 L120,0 L120,80 L0,80 Z", "windingRule": "NONZERO" },
    { "data": "M30,20 L90,20 L90,60 L30,60 Z", "windingRule": "EVENODD" }
  ],
  "fills": [{ "kind": "solid", "color": "#ff7e00" }],
  "ariaLabel": "Frame with cutout"
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `geometry` | `"rect"` \| `"circle"` \| `"path"` | yes | Shape kind. |
| `size` | `{ w, h }` | conditional | Required for `rect`/`circle`. Recommended for `path` so renderers can compute a viewBox without parsing every subpath. |
| `pathData` | string | conditional | Single-path shorthand. Required for `path` when `paths` is absent. SVG path `d` attribute syntax. Equivalent to `paths: [{ data: <pathData>, windingRule: "NONZERO" }]`. Mutually exclusive with `paths`. |
| `paths` | array of `{ data: string, windingRule?: "NONZERO" \| "EVENODD" }` | conditional | (1.1+) Multi-subpath geometry. Required for `path` when `pathData` is absent. Each entry is an SVG path with its own winding rule (default `"NONZERO"`). Fills and strokes apply to the union of all subpaths. Use this form for `BooleanOperation`-style flattened geometry from authoring tools. Mutually exclusive with `pathData`. |
| `fill` | CSS color | no | Single solid fill. Mutually exclusive with `fills`. |
| `fills` | array of [Fill](#412-fill-spec) | no | (1.1+) Stacked fills, top-to-bottom (the first entry renders on top). Mutually exclusive with `fill`. Supports solid colors, linear gradients, radial gradients. |
| `stroke` | `{ color, width }` | no | Single stroke. Mutually exclusive with `strokes`. |
| `strokes` | array of `{ color, width }` | no | (1.1+) Stacked strokes, top-to-bottom. Mutually exclusive with `stroke`. |
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

### 4.9 `instance` (1.1+)

Mounts a sub-scene by id, with bound parameters. The instance is the universal "composite reuse" primitive — a scene fragment that lives in a separate bundle and is included by reference here.

```json
{
  "kind": "instance",
  "scene_id": "scoreboard-template",
  "scene_version": "sha256:c4b9...",
  "params": {
    "team_a": "Alpha",
    "team_b": "Beta",
    "score_a": 14,
    "score_b": 12
  },
  "fit": "contain"
}
```

| Prop | Type | Required | Description |
|---|---|---|---|
| `scene_id` | SceneId | yes | The bundle's `scene_id` to instantiate. |
| `scene_version` | SceneVersion | yes | Pinned content hash. Forward-compat : runtime that can't fetch this exact version triggers `BUNDLE_FETCH_FAILED`. |
| `params` | object | no | Free-form parameters passed to the instantiated scene. The host scene's runtime makes these visible to the instance under the `__params.*` reserved namespace (see §4.9.1). |
| `params.<key>` value | any LeafValue | — | Same allowed types as snapshot/delta values (LSDP §3.2.1). |
| `bindParams` | object | no | Per-key bind to LeafPaths. Lets params be reactive — the instance updates as the host's leaf values change. Mutually exclusive per-key with the static `params` value. |
| `fit` | `"contain"` \| `"cover"` \| `"fill"` \| `"none"` | no | How to fit the instance's design surface within the slot if aspect ratios differ. Default `"contain"`. |
| `size` | `{ w, h }` | no | Override slot size. Defaults to the instance's intrinsic size from its bundle's root frame. |
| `position` | `{ x, y }` | no | Slot position. Default `{0,0}`. |

#### 4.9.1 The `__params.*` namespace

When a runtime mounts an `instance`, it makes the `params` map (and the resolved `bindParams` values) visible to the instance's tree under `__params.*` leaf paths. Inside the instance bundle, primitives bind to `__params.team_a`, `__params.score_a`, etc. — the same way they bind to any leaf.

`__params.*` is a reserved namespace per LSDP/1 §10. The runtime injects values from the host ; the instance bundle MAY NOT declare it in `operator_inputs` (params are host-controlled, not operator-driven).

#### 4.9.2 Recursion limits

Instances MAY recurse (an instance bundle can itself contain instances). The runtime SHOULD impose a depth limit (recommended: 8) and reject bundles whose effective depth exceeds it via `BUNDLE_INCOMPATIBLE`. Cyclic references (A instances B instances A) MUST be rejected.

#### 4.9.3 Fetch model

The host bundle MUST declare every instance's `scene_version` in `assets.preload` (or via the runtime's bundle fetcher) so the runtime can resolve the inner bundle before mounting. A failed fetch produces `BUNDLE_FETCH_FAILED` ; the instance renders nothing until the fetch succeeds.

### 4.10 Reserved primitive `kind` values

The closed core catalog of LSML 1.x is :

```
stack, grid, frame, text, image, shape, media, repeat, instance
```

Implementations MUST support all 9. Implementations MUST NOT add `kind` values outside this set unless they prefix them with `x-<vendor>.` (see §17.1 vendor-prefixed extensions).

### 4.11 (reserved)

### 4.12 Fill spec

The `Fill` type (used by `shape.fills[]` and `frame.backgrounds[]` in 1.1+) is a discriminated union :

```json
// solid color
{ "kind": "solid", "color": "#ff0000", "opacity": 0.8 }

// linear gradient
{
  "kind": "linear-gradient",
  "angle_deg": 90,
  "stops": [
    { "offset": 0.0, "color": "#ff7e00" },
    { "offset": 0.5, "color": "#ff3366", "opacity": 0.9 },
    { "offset": 1.0, "color": "#ff1a3d" }
  ]
}

// radial gradient
{
  "kind": "radial-gradient",
  "center": { "x": 0.5, "y": 0.5 },
  "radius": 0.5,
  "stops": [
    { "offset": 0.0, "color": "#ffffff" },
    { "offset": 1.0, "color": "#000000" }
  ]
}
```

| `kind` | Required fields | Optional fields |
|---|---|---|
| `solid` | `color` (CSS color) | `opacity` (0..1) |
| `linear-gradient` | `stops` (≥ 2 items) | `angle_deg` (default `0` = bottom-to-top), `opacity` |
| `radial-gradient` | `stops` (≥ 2 items) | `center` (default `{0.5, 0.5}` — relative to bounding box), `radius` (default `0.5` — relative to longest bbox dim), `opacity` |

Each `stop` is `{ offset: number 0..1, color: CSS color, opacity?: number 0..1 }`. Stops MUST be sorted by `offset` ascending. The first MUST have `offset: 0` ; the last MUST have `offset: 1`.

Color interpolation between stops happens in **sRGB** space (LSML 1.1 default — see §6.5 for animation interpolation choice). Future profiles MAY opt into perceptual color spaces (`OKLCH`, `Lab`) via the §17.3 profiles mechanism.

A 1.0 receiver encountering `fills[]` or `backgrounds[]` falls back to the legacy `fill` / `background` field (the bundle SHOULD provide both). When neither is present, the runtime renders no fill.

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

### 5.4 Universal props (1.1+)

Five props apply to **every** primitive in the catalog (§4.1–4.9), regardless of `kind`. They control rendering attributes that are universal across visual types.

```json
{
  "kind": "text",
  "bind": { "value": "score" },
  "position": { "x": 320, "y": 80 },
  "visible": true,
  "sizing": { "x": "fill", "y": "hug" },
  "opacity": 0.9,
  "rotation": 5
}
```

| Prop | Type | Default | Description |
|---|---|---|---|
| `position` | `{ x: number, y: number }` | `{0,0}` | (1.1+) Absolute position relative to the parent's coordinate origin. Honoured when the parent is a `frame` (absolute layout) or any container in absolute mode. Ignored by `stack` and `grid` parents — those layouts own child placement. The `frame` and `image` primitives also document a per-primitive `position` (§4.3, §4.5) for back-compat ; semantics are identical. |
| `visible` | boolean | `true` | When `false`, the primitive (and its subtree, if any) is not rendered. The slot collapses in flex layouts. |
| `sizing` | `{ x: SizingMode, y: SizingMode }` | `{ "fixed", "fixed" }` | Auto-layout sizing intent per axis when the primitive lives inside a flex container (`stack` or `frame` with auto-layout). |
| `opacity` | number 0..1 | `1` | Composite alpha. Applied multiplicatively with `animate.opacity` if both are present. |
| `rotation` | number (degrees) | `0` | Static rotation around the primitive's centre. Applied in addition to `animate.transform.rotate`. |

#### 5.4.1 `SizingMode` enum

```
"fixed" | "hug" | "fill"
```

| Value | Semantics |
|---|---|
| `fixed` | The primitive honours its declared `size` / dimensions verbatim. |
| `hug` | The primitive shrinks to fit its intrinsic content. The flex container hands the child its preferred size. |
| `fill` | The primitive grows to fill the available space along the container's main axis. Multiple `fill` siblings split the slack evenly. |

`sizing` is a hint to the parent flex layout. It has no effect on the root frame (which is always `fixed` to its declared `size`) or on children of `grid` (which use `gridArea`).

#### 5.4.2 Bindable universal props (1.1+)

`visible`, `opacity`, and `rotation` accept the bind pattern when reactive behaviour is needed :

```json
{
  "kind": "image",
  "bind": { "src": "team.logo.url" },
  "bindUniversal": {
    "visible": "ui.show_logo",
    "opacity": "ui.fade_amount"
  }
}
```

`bindUniversal` mirrors `bindStyle` (§5.2) — keys are universal-prop names, values are LeafPaths. The runtime resolves the path against the store and re-renders on change. Static and bound forms are mutually exclusive per key.

`sizing` is NOT bindable in 1.1 (auto-layout depends on it for first-paint ; reactive sizing introduces layout thrash). A future minor MAY add it after profiling.

`position` is also NOT bindable in 1.1.x. Reactive absolute position is real (animating a sticker) but better expressed via `animate.transform.translate` (§6.1), which already supports binding. Adding `bindUniversal.position` would create two ways to do the same thing.

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

### 6.5 Color interpolation (1.1+)

Animations targeting color-typed properties (`text.style.color`, `shape.fill`, `shape.fills[].color`, `frame.background`, `frame.backgrounds[]`, etc., reachable via `bindAnimate` or per-leaf `transition` directives in `delta` frames) interpolate between values in **sRGB** color space.

**Algorithm** :

1. Both endpoints are parsed to RGBA channels in the [0, 1] range (per [CSS Color Module Level 4](https://www.w3.org/TR/css-color-4/)). Hex (`#rrggbb`, `#rrggbbaa`), `rgb()`/`rgba()`, `hsl()`/`hsla()`, and named colors all parse correctly.
2. Channels are linearly interpolated component-wise : `out_c = a_c + t * (b_c - a_c)` for `c ∈ {r, g, b, a}`, with `t ∈ [0, 1]` produced by the easing curve.
3. The output RGBA is serialised back to `#rrggbbaa` or `rgba()` form for compositing.

**Why sRGB** : it is universally supported, predictable, and well-understood. Implementations MAY offer perceptually-uniform color spaces (OKLCH, OKLab, CIELab) via the §17.3 profiles mechanism — bundles that opt in get smoother gradients in mid-range hues at the cost of platform inconsistency.

**Discontinuities** : interpolating between very different hues in sRGB can pass through a desaturated midpoint (the "grey middle" effect). Authors who care about this SHOULD chain shorter animations between hue-adjacent waypoints, or opt into a perceptual profile.

A 1.0 runtime cannot interpolate colors and snaps to the target value instantly. This is a quality regression but not a correctness one ; bundles that depend on color interp MUST declare `lsml: "1.1"`.

### 6.6 Keyframe sequences (1.1+)

A primitive MAY declare a `keyframes` sequence as a multi-step alternative to single-target `animate`. The sequence describes a path through animatable property values over time, applied once on (re)mount or whenever the keyframe key changes.

```json
{
  "kind": "frame",
  "keyframes": {
    "key": "ui.modal.open",
    "steps": [
      { "at": 0,    "transform": { "scale": 0.8 }, "opacity": 0 },
      { "at": 0.6,  "transform": { "scale": 1.05 }, "opacity": 1 },
      { "at": 1,    "transform": { "scale": 1 } }
    ],
    "duration_ms": 300,
    "easing": "ease-out"
  }
}
```

| Field | Required | Description |
|---|---|---|
| `key` | optional | LeafPath whose value, when changed, replays the sequence from `at: 0`. When absent, the sequence runs only on (re)mount. |
| `steps` | yes | Array of step objects, sorted by `at` ascending. First step MUST have `at: 0` ; last MUST have `at: 1`. |
| `steps[].at` | yes | Timeline position (0..1, normalised over `duration_ms`). |
| `steps[].transform` / `opacity` / `filter` | each optional | Same shapes as `animate.transform` / `animate.opacity` / `animate.filter`. |
| `duration_ms` | yes | Total sequence duration in milliseconds. |
| `easing` | no | Curve applied between consecutive steps. Default `linear`. |

Keyframe sequences and the static `animate` block MAY coexist on the same primitive — `keyframes` plays out on mount/key-change, and `animate` controls steady-state targets afterwards. Combining them MUST NOT cascade : the runtime applies whichever was last triggered, no blending.

A 1.0 runtime ignores `keyframes` (the primitive renders without the multi-step animation). The bundle MAY include both `keyframes` and a fallback `animate` static for graceful degradation.

### 6.7 Stagger (1.1+)

A `repeat` primitive MAY declare a `stagger_ms: number` field. When set, each iteration's animations (whether from `animate`, `keyframes`, or `bindAnimate`) start `index * stagger_ms` after the previous iteration's start. This produces wave-like reveals (each row fading in 50 ms after the previous) without per-iteration scripting.

```json
{
  "kind": "repeat",
  "bind": { "items": "players" },
  "scope": "player",
  "stagger_ms": 80,
  "template": {
    "kind": "stack",
    "animate": { "opacity": 1 },
    "children": [ ... ]
  }
}
```

`stagger_ms: 0` is the implicit default — all iterations animate simultaneously.

The runtime MAY cap effective stagger at a sane upper bound (e.g. `index * stagger_ms ≤ 2000ms`) to prevent pathological wait times for large lists.

A 1.0 runtime ignores `stagger_ms` ; all iterations animate simultaneously.

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

## 16. (reserved)

Reserved for future numbering — keeps §17 stable across minor revisions.

---

## 17. Extension mechanisms (1.1+)

LSML's core catalog (the 9 primitives in §4 + the 5 adapter kinds in §9.1) is intentionally small. Real-world deployments often need vendor- or domain-specific extensions that don't make sense to standardize. This section formalises the four mechanisms LSML provides for extension without forking the format.

The mechanisms are layered : prefer the earlier ones whenever possible. Composition (§17.0) covers ~80% of needs, vendor extensions (§17.1, §17.2) cover most of the rest, profiles (§17.3) and metadata (§17.4) handle the long tail.

### 17.0 Composition (preferred — no spec change needed)

Most extensions are not new primitives at all — they decompose into the existing catalog plus an `external_adapter` that pushes data onto leaf paths.

| Domain need | Decomposition |
|---|---|
| Live chat overlay | `stack { repeat { stack { image avatar + text user + text message } } }` + adapter pushing `chat.messages[]` |
| Real-time chart | `frame { repeat { shape kind=path d=<computed> } }` + adapter pushing `chart.series[].path_d` (server-side path computation) |
| Logical engine output | `text` (or `image`/`shape`) bound to a leaf path + adapter polling the engine's output |
| Camera/video source switch | `media kind=video` + bind `src` on a leaf path + adapter that updates the leaf when the source changes |
| Data table / leaderboard | `stack { repeat { stack { text + text + text } } }` over a server-sorted array |

This mechanism requires nothing from the format beyond what already exists. Adopting it is the lowest-friction path for a vendor.

### 17.1 Vendor-prefixed primitive `kind` values (1.1+)

When composition truly cannot express a visual (e.g. a 3D scene, an interactive node graph editor, a heatmap with custom palette logic, an embedded iframe), a vendor MAY introduce a custom primitive whose `kind` starts with `x-<vendor>.<name>` :

```json
{ "kind": "x-acme.heatmap", "data_path": "metrics.matrix", "colormap": "viridis" }
{ "kind": "x-zab.live-graph", "binding_id": "...", "x-zab.refresh_ms": 100 }
{ "kind": "x-acme.iframe", "src": "https://...", "sandbox": "allow-scripts" }
```

#### 17.1.1 Naming

- The prefix MUST be `x-` (lowercase), followed by a vendor identifier matching `[a-z][a-z0-9_-]*`, followed by a dot, followed by a primitive name matching `[a-z][a-z0-9_-]*`.
- A vendor identifier SHOULD be a stable, reserved prefix (e.g. `x-acme.*` is reserved by Acme Corp and only Acme primitives use it). Collisions are the vendor's responsibility ; the format does not adjudicate.
- Custom prop names within an `x-vendor.*` primitive SHOULD also use the `x-vendor.` prefix to make their non-portable origin obvious. Standard universal props (`visible`, `sizing`, `opacity`, `rotation`) MAY be used unprefixed.

#### 17.1.2 Validation behaviour

- A runtime that recognises the `x-vendor.<name>` value renders it normally.
- A runtime that does NOT recognise the value MUST emit `BUNDLE_INCOMPATIBLE` (per §15.1) — the same strict fallback as for unknown standard `kind` values.
- Bundles using vendor primitives are **non-portable** : they require a runtime that ships the vendor's plugin. The vendor SHOULD document this clearly (typically via `profiles[]` — see §17.3 — to make the dependency machine-readable).

#### 17.1.3 Why strict (not lenient)

Rendering a partial tree with unknown primitives invisibly skipped would mislead the operator about what's on screen. LSML inherits this from §15.1 — strict fallback is the format's general posture.

### 17.2 Vendor-prefixed adapter kinds (1.1+)

§9.1 closes the adapter `kind` list to 5 standard kinds (`http_poll`, `websocket_subscribe`, `pg_listen`, `webhook_receive`, `cron`). Vendors MAY introduce custom adapter kinds using the same `x-<vendor>.<name>` convention :

```json
{ "kind": "x-zab.blueprint_execute", "binding_id": "...", "writes_to": "data" }
{ "kind": "x-acme.kafka_consume", "topic": "events", "writes_to": "events" }
```

Adapter execution is server-side. A server that does NOT recognise the `kind` SHOULD log a warning and either decline to serve the scene OR serve it with the affected paths empty. The bundle remains valid LSML — adapters are server-internal, so unknown kinds don't produce client-detectable errors.

Validators MAY require a per-kind schema at `spec/adapters/<kind>.json` for the standard 5, but MUST accept `x-<vendor>.*` adapters with arbitrary additional properties (the vendor's schema is the contract).

### 17.3 Profiles (1.1+)

A bundle MAY declare top-level `profiles: [string]` listing capability profiles it requires for correct rendering :

```json
{
  "lsml": "1.1",
  "scene_id": "main-stage",
  "scene_version": "sha256:...",
  "profiles": ["x-acme.broadcast/1.0", "x-lumencast.color-oklch/1"],
  "layout": { ... }
}
```

Each profile is a string identifier of the form `x-<vendor>.<name>/<version>` where `<version>` is `<major>` or `<major>.<minor>`. A profile groups behaviour conventions or feature flags that go beyond strict LSML conformance — e.g. "this bundle assumes a 16:9 broadcast aspect ratio with safe-area padding", or "interpolate colors in OKLCH instead of sRGB".

#### 17.3.1 Profile resolution

- A runtime MUST publish the list of profiles it supports (typically via its `/test/health` endpoint or a vendor-specific manifest).
- When loading a bundle, the runtime checks every entry in `profiles[]` against its supported list :
  - All supported → render normally with profile-specific behaviour
  - At least one unsupported → MUST reject with `BUNDLE_INCOMPATIBLE` (the bundle author signaled this is a hard requirement)

#### 17.3.2 Standard profiles

LSML 1.1 defines no standard profiles. Future minor revisions or vendor specs MAY register profiles (e.g. `x-lumencast.color-oklch/1.0` to switch animation/gradient color interpolation from sRGB to OKLCH).

#### 17.3.3 Naming

Profile identifiers follow the same `x-<vendor>.<name>` convention as primitive `kind` values, suffixed with `/<version>`. The `x-lumencast.*` prefix is reserved for officially-blessed Lumencast extension profiles.

### 17.4 The `metadata` field (universal escape hatch)

The `metadata` field (top-level on the bundle, and per-primitive when needed) is open-ended. Vendors MAY use it for authoring information that the runtime never consumes :

```json
{
  "metadata": {
    "author": "alice",
    "tags": ["broadcast", "live"],
    "acme": {
      "editor_locked_layers": ["layer-3"],
      "thumbnail_seed": 42
    },
    "zab": {
      "scene_template_id": "..."
    }
  }
}
```

Runtimes MUST ignore `metadata` for rendering decisions — it is documentation and authoring state only.

Naming convention for vendor-specific keys :

- A vendor SHOULD nest its keys under a single sub-object whose key is the vendor's stable lowercase identifier (`metadata.<vendor>.*`). The vendor identifier matches `[a-z][a-z0-9_-]*`.
- The `x-` prefix used elsewhere in §17 (kind values, adapter kinds, profile identifiers, etc.) is NOT required inside `metadata` — `metadata` is itself the namespace, so `metadata.<vendor>.*` is unambiguous.
- Top-level keys without a vendor namespace (`author`, `description`, `tags`, …) are reserved for generic authoring metadata. Vendors SHOULD NOT shadow them.

Per-primitive metadata follows the same convention :

```json
{
  "kind": "image",
  "bind": { "src": "..." },
  "alt": "Logo",
  "metadata": {
    "acme": { "constraints": { "horizontal": "SCALE", "vertical": "SCALE" } }
  }
}
```

The runtime ignores the per-primitive `metadata` block as well — it is round-trip-only state for authoring tools.

### 17.5 Authoring profiles

An **authoring profile** is a §17.3 profile dedicated to the round-trip contract between an authoring tool and a renderer. It exists because LSML's core primitive catalog (§4) cannot carry every source-fidelity property an authoring tool might want to preserve — effects, blend modes, masks, fine-grained layout flags, vendor-specific transforms — and §17.4 alone leaves the metadata shape unspecified.

An authoring profile :

- Declares a profile identifier `x-<vendor>.authoring/<major>` (e.g. `x-acme.authoring/1`).
- Specifies which `metadata.<vendor>.*` keys an authoring tool emits, their types, and the rendering behaviour an aware consumer SHOULD reproduce.
- Lives in `spec/profiles/<vendor>-authoring.md` in this repository, or in the vendor's own repository with a normative reference back.

The mechanism stitches §17.3 (capability declaration) and §17.4 (vendor metadata) into a single contract :

1. The bundle declares `profiles: ["x-<vendor>.authoring/1"]` to signal the contract.
2. The authoring tool emits `metadata.<vendor>.*` keys per the profile.
3. A profile-aware renderer reads those keys to reproduce source-fidelity properties (effects, blend modes, masks, custom layout flags, …) that LSML's core catalog cannot carry natively.
4. A non-aware renderer ignores the metadata per §17.4 and renders the underlying primitives best-effort. The bundle still validates structurally.

#### 17.5.1 Advisory semantics — exception to §17.3

§17.3 specifies that an unsupported entry in `profiles[]` MUST trigger `BUNDLE_INCOMPATIBLE` rejection. **Authoring profiles override that rule** : a renderer that does not support `x-<vendor>.authoring/<major>` MUST NOT reject the bundle, MUST NOT emit `BUNDLE_INCOMPATIBLE`, and MUST render the underlying LSML primitives as if the profile were absent.

The rationale is that authoring profiles describe **enrichments** layered on top of a structurally complete LSML bundle. The bundle stays renderable without them ; the profile only adds source-fidelity that a generic renderer cannot reproduce anyway. Rejecting the bundle would be strictly worse than partial rendering.

Behavioural profiles (color space, layout convention, etc. — typical §17.3 profiles) keep §17.3's rejection semantics : their absence changes the rendered result substantively. Authoring profiles do not.

A renderer detects authoring profiles by the `.authoring/` segment in the identifier (i.e. `<vendor>.authoring/<major>`). Identifiers without this segment follow §17.3 strict rejection.

#### 17.5.2 Round-trip stability

Two implementations of the same authoring profile SHOULD produce **byte-equivalent** output after canonicalisation when given the same logical input. Achieving this requires :

- All `metadata.<vendor>.*` keys declared by the profile are preserved verbatim across import → export.
- Float values are rounded consistently (the §3.1 canonicalizer's rounding applies to the whole bundle).
- Arrays whose order matters (effects, gradient stops, gradient transforms, per-corner radii, layer ordering, …) preserve source order. The profile MUST document any array whose order is semantic.

Round-trip stability is the property that makes a bundle a shareable artefact between authoring tools, enrichment editors, and renderers. Without it, every round-trip churns the canonical bytes and breaks content-addressing (§3).

#### 17.5.3 Profile evolution

Authoring profiles follow the same versioning pattern as §17.3 profiles :

- Backward-incompatible changes bump the major (`x-<vendor>.authoring/2`).
- Additive changes (new optional keys) keep the same identifier — readers MUST ignore unknown keys.
- Deprecated keys SHOULD remain documented for at least one major (parallel reads) before removal, to give downstream consumers a migration window.

#### 17.5.4 Cross-vendor adoption

The pattern is intentionally vendor-neutral. Multiple authoring profiles MAY coexist in a single bundle's `profiles[]` (an enrichment tool that works on top of any authoring source declares the source's profile in addition to its own). Each profile's `metadata.<vendor>.*` block is independent ; the metadata namespace ensures no cross-vendor key collisions.

### 17.6 Decision flow for extensions

When a developer needs to add a non-trivial feature, they choose between mechanisms in this order :

1. **Composition** (§17.0) — does the feature reduce to existing primitives + an adapter ? Use that. Zero spec change. The bundle stays portable.
2. **Vendor primitive** (§17.1) — is it a truly atomic visual that can't be composed ? Add an `x-<vendor>.<name>` primitive. Bundle becomes non-portable but the format is unchanged.
3. **Vendor adapter** (§17.2) — is it server-side data plumbing that can't fit the standard 5 kinds ? Add an `x-<vendor>.<name>` adapter. Bundle stays portable on the wire, the server alone needs the plugin.
4. **Profile** (§17.3) — is the feature a behaviour mode rather than a primitive (e.g. color space, layout convention) ? Declare a profile.
5. **Authoring profile** (§17.5) — is the feature about round-tripping source-fidelity properties from an authoring tool that don't fit the LSML core catalog ? Declare an authoring profile and emit `metadata.<vendor>.*` per the profile contract.
6. **Metadata** (§17.4) — is it pure ad-hoc authoring state with no profile contract and no runtime impact ? Park it in `metadata`.

If none of these fit, the developer is hitting LSML's domain edge — the right move is to use LSDP for the data plane only and write a custom renderer (see §15.4 in `lumencast-protocol/briefs/` for the four-tier developer guide).

---

## 18. On-disk format

A scene bundle is **a JSON document** (RFC 8259). LSML defines no syntax of its own ; the *format* is JSON, the *schema* is LSML, the *brand* is `.lsml`. This section formalises the on-disk and on-the-wire conventions for storing and exchanging bundles.

### 18.1 File extension

| Extension | Status | Use |
|---|---|---|
| `.lsml` | preferred | Primary extension for scene bundles. |
| `.lsml.json` | accepted | Alternative form ; explicit dual extension makes the JSON nature obvious to legacy tooling. Treated as identical to `.lsml`. |
| `.json` | accepted | Tolerated for legacy or generic-tooling contexts. Producers SHOULD prefer `.lsml`. |

A bundle's bytes MUST be valid JSON regardless of the chosen extension. There is no `.lsml`-specific syntax extension : an `.lsml` file opened in any JSON parser parses cleanly.

### 18.2 Media type

The IANA-style media type for a Lumencast scene bundle is :

```
application/lsml+json
```

The `+json` suffix per [RFC 6839](https://www.rfc-editor.org/rfc/rfc6839) declares JSON as the structural syntax. HTTP servers serving bundles SHOULD set `Content-Type: application/lsml+json ; charset=utf-8`. Clients MAY also accept `application/json` to remain interoperable with generic tools.

For bundles transferred over LSDP frames (§LSDP-1.md), the wire format is opaque — bundles are JSON values nested inside frame payloads, not standalone documents. Media-type negotiation only applies to standalone exchanges (REST APIs, file uploads, GraphQL).

### 18.3 Encoding

Bundles MUST be encoded as **UTF-8** without BOM, per RFC 8259 §8.1. Producers MUST NOT emit a UTF-8 BOM ; consumers SHOULD strip one if present for robustness.

Line endings are NOT normative. JSON parsers ignore trailing whitespace, so `LF` and `CRLF` are both accepted. The canonical form (§3.1, JCS) emits no trailing newline.

### 18.4 The `$schema` field

LSML bundles SHOULD declare a top-level `$schema` field pointing at the JSON Schema URL for the version they conform to :

```json
{
  "$schema": "https://lumencast.dev/schema/lsml/1.1/schema.json",
  "lsml": "1.1",
  ...
}
```

The **canonical** schema URL convention is :

```
https://lumencast.dev/schema/lsml/<major>.<minor>/schema.json
```

This URL space is reserved for stable, hosted schema documents. **Until `lumencast.dev` hosts the schema**, the canonical URL serves as the schema's logical identifier (`$id`) but does not resolve to bytes. To enable IDE autocomplete *today*, bundles MAY use the GitHub raw URL as a transport-equivalent fallback :

```
https://raw.githubusercontent.com/Lumencast/lumencast-protocol/v<release-tag>/spec/schema.json
```

— or, for floating-on-`main` autocomplete during development :

```
https://raw.githubusercontent.com/Lumencast/lumencast-protocol/main/spec/schema.json
```

Both URLs serve byte-identical content as `lumencast.dev/schema/lsml/<v>/schema.json` once hosting is in place. Authors who pin to a release tag (`v1.0.1`, `v1.1`, etc.) get reproducible validation ; floating `main` is convenient for spec contributors but couples the bundle's editor experience to ongoing spec churn.

#### 18.4.1 Editor support

Editors with JSON Schema support auto-resolve `$schema` URLs and provide structural validation, autocomplete of property names and enum values, and inline documentation hovers (sourced from `description` fields in the schema). The following editors are known to work :

- **VS Code** — built-in JSON language service. `$schema` is fetched and cached automatically.
- **JetBrains IDEs** (IntelliJ, WebStorm, PyCharm, …) — built-in JSON Schema support.
- **Vim** with `coc-json`, or **Neovim** with `nvim-lspconfig` + `vscode-json-languageserver`.
- **Sublime Text** with `LSP-json`.
- **Helix** — built-in via `vscode-json-languageserver`.

For workspaces that need custom schema mapping (e.g. associating `*.lsml` files with the schema regardless of the `$schema` field), VS Code users can configure `settings.json` :

```jsonc
{
  "json.schemas": [
    {
      "fileMatch": ["*.lsml"],
      "url": "https://raw.githubusercontent.com/Lumencast/lumencast-protocol/main/spec/schema.json"
    }
  ]
}
```

#### 18.4.2 Semantics

`$schema` is **informational only** — runtimes MUST ignore it for rendering and validation decisions (the version-of-record is `lsml`, not the URL). A bundle without `$schema` is fully valid ; the field exists purely to enable the editor experience.

The `$schema` field SHOULD be the **first** key in the JSON object so file-detection heuristics that read the prefix can recognise the document. `lsml` MUST appear within the first 3 keys.

### 18.5 Magic-key detection

A consumer that needs to detect "is this an LSML bundle ?" without relying on filename or media type can read the JSON and check :

- top-level field `lsml` exists, AND
- its value matches `^1\.\d+$` (or whatever range the consumer supports)

This is sufficient to disambiguate from arbitrary JSON. The `lsml` field is present in every bundle (it is required by the schema).

For binary detection (file managers, magic-byte sniffers), the first non-whitespace bytes of an LSML bundle are always `{` followed eventually by `"$schema"` or `"lsml"`. There is no LSML-specific magic byte sequence — this is intentional, to keep the format trivially convertible from generic JSON.

### 18.6 Authoring affordances

JSON does not natively support comments. For authoring, two paths exist :

1. **JSON-with-comments (JSONC)** — strip comments at load time. VS Code and many other editors support `.json` files with `//` and `/* */` comments via the `jsonc` parser. **JSONC is NOT a normative LSML feature.** A bundle that contains comments MUST be JSONC-stripped before being shipped to a runtime ; runtimes only accept strict RFC 8259 JSON. Authors MAY use JSONC locally and pre-process before publishing.
2. **`metadata` field** — the open-ended `metadata` object (§1) is a runtime-ignored escape hatch for authoring annotations (author, description, tags, editor state). Future-proof for any non-runtime data.

If a richer authoring layer is needed in the future (templates, interpolation, includes), it will be introduced as a separate compile-to-LSML toolchain (`lsml-fmt` or similar), NOT as a change to the on-disk format. The on-disk format stays JSON.

### 18.7 Compression

For network transport, bundles SHOULD be served with HTTP `Content-Encoding: gzip` or `br`. JSON compresses well (typically 5–15× ratio) ; uncompressed transfers are wasteful.

For at-rest storage, bundles are typically small enough that compression is unnecessary. Storage layers that compress whole columns (e.g. Postgres TOAST) handle this transparently.

### 18.8 Example

A minimal bundle saved as `hello.lsml` :

```json
{
  "$schema": "https://lumencast.dev/schema/lsml/1.1/schema.json",
  "lsml": "1.1",
  "scene_id": "hello",
  "scene_version": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "layout": {
    "kind": "frame",
    "size": { "w": 1920, "h": 1080 },
    "background": "#000",
    "children": [
      {
        "kind": "text",
        "bind": { "value": "title" },
        "style": { "fontSize": 48, "color": "#fff", "textAlign": "center" }
      }
    ]
  },
  "defaults": { "title": "Hello, Lumencast" }
}
```

Open this file in VS Code with the JSON language service active, and `$schema` resolution gives autocomplete + validation immediately, no extension needed.

---

## Reference

- [JSON Schema for LSML 1.x](schema.json) (canonical machine-readable spec)
- [LSDP/1 wire protocol](LSDP-1.md) (how bundles travel)
- [Error code taxonomy](ERROR-CODES.md)
- [Conformance suite](../conformance/README.md)
