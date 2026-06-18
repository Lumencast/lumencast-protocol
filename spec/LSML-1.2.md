# LSML 1.2 — additive extensions over 1.1

> **Status** : 1.2 — additive over 1.1. Promotes four families that 1.1 could only
> stash in `metadata.figma.*` into **core, rendable** constructs : per-primitive
> **blend modes**, a **typed mask**, a **first-class image-fill**, and a **gradient
> transform**. Every addition is optional at the JSON level *but* the four families
> are **mandatory features of a conforming 1.2 renderer** (ADR 002 §3.2 — they are
> jointly required for zero-loss transcription of `817:3`). A 1.1 bundle stays valid
> and renders unchanged ; opt into 1.2 with `lsml: "1.2"`.
>
> **Source of decision** : ADR 002 (`lumencast-js/docs/adr/002-…`), §3.2 / §3.4.
> **Security** : Bastion threat-model conditions T1–T4 (2026-06-17) are normative on
> the constructs below. The runtime+compiler enforcement lives in `lumencast-js`
> (`packages/protocol/src/host-allow.ts`, `packages/compiler/src/lsml-1_2.ts`).
>
> **Conformance keyword convention** : **MUST**, **MUST NOT**, **SHOULD**, **MAY** per
> [RFC 2119]. This document is additive — read it alongside `LSML-1.md` ; section
> numbers below extend the 1.1 catalog, they do not replace it.

## 1. Versioning

A 1.2 bundle declares `lsml: "1.2"`. The `schema.json` `lsml` enum accepts `"1.0"`,
`"1.1"`, `"1.2"`. All 1.2 fields are additive : a 1.1 receiver that ignores them
renders a structurally valid scene (degraded, but never broken). A 1.2 receiver MUST
honour all four families below.

## 2. `blendMode` (universal, 1.2+)

Every primitive MAY carry a `blendMode` string. It lowers to CSS `mix-blend-mode`.

- **Type** : closed enum, faithful to Figma minus `PASS_THROUGH`.
- **Values** : `normal`, `multiply`, `screen`, `overlay`, `darken`, `lighten`,
  `color-dodge`, `color-burn`, `hard-light`, `soft-light`, `difference`, `exclusion`,
  `hue`, `saturation`, `color`, `luminosity`.
- **Enforcement (T4)** : a value outside this set MUST be rejected — diagnostic +
  omission, **never passthrough**. The compiler and the runtime both gate it (the live
  LSDP delta path bypasses the compiler). `$defs/BlendMode` in `schema.json`.

```json
{ "kind": "shape", "geometry": "rect", "blendMode": "hard-light", "fills": [ … ] }
```

## 3. `mask` (universal, 1.2+)

Every primitive MAY carry a typed `mask`. The runtime builds an SVG `<mask>` /
`<clipPath>` from its **typed fields** — there is deliberately **no free-form SVG
string** anywhere in this shape (Bastion **T3** : `dangerouslySetInnerHTML` / `innerHTML`
on bundle content is forbidden ; `foreignObject` / `script` / event-handlers are
structurally impossible). `mask` supersedes `clipsContent` for non-rectangular cases.

| Field | Type | Req | Description |
|---|---|---|---|
| `source` | `{ kind:"shape"; ref }` \| `{ kind:"image"; src }` \| `{ kind:"group"; ref }` | yes | Mask coverage : a sibling shape by `id`, an image asset, or a sibling GROUP/FRAME container by `id` (composite of its visible children). |
| `type` | `"alpha"` \| `"luminance"` | yes | Channel read from the source. |
| `op` | `"intersect"` \| `"subtract"` \| `"union"` | yes | Boolean composition against the masked content. |
| `position` | `{ x, y }` | no | Placement of the source within the masked box. |
| `size` | `{ w, h }` | no | Explicit source size. |

- **Enforcement (T4)** : a bad `type` / `op` / source discriminant MUST drop the whole
  mask (it cannot be partially honoured) — diagnostic, never passthrough.
- **Enforcement (T1/T2)** : a `source.kind === "image"` `src` MUST pass the asset URL
  gate (§5) before reaching the DOM. `$defs/Mask` in `schema.json`.
- **`source.kind === "group"` (1.2+, ADR 002 A4.3)** : `ref` is the `id` of a sibling
  GROUP/FRAME container. The runtime composites the **union** of the coverage geometry of
  the container's **visible** direct children (`visible !== false`). Anti-cycle : only the
  children's own geometry is inlined, never their or the container's own `mask` (resolution
  depth = 1). A descent / N cap bounds the composite — beyond it, truncation + diagnostic,
  never an unbounded build (T5). A pending `ref` or an empty container → mask omitted, no
  crash. The builder stays 100 % typed (T3).

```json
{ "kind": "shape", "geometry": "rect",
  "mask": { "source": { "kind": "image", "src": "https://cdn.example.com/ellipse.png" },
            "type": "alpha", "op": "intersect" } }
```

## 4. First-class image-fill + gradient transform (§4.12 extension, 1.2+)

### 4.1 Image-fill

`LSMLFill` gains a fourth discriminant `kind: "image"`, valid anywhere a fill is —
`shape.fills[]` and `frame.backgrounds[]`. It unifies the frame image-background and
unblocks the shape image-fill that 1.1 dropped. The `image` *primitive* remains for
an image-as-node.

| Field | Type | Req | Description |
|---|---|---|---|
| `kind` | `"image"` | yes | Discriminant. |
| `src` | asset URL | yes | Gated by §5 (T1/T2). |
| `objectFit` | `"cover"`\|`"contain"`\|`"fill"`\|`"none"`\|`"scale-down"` | no | Closed enum → CSS `object-fit`. Out-of-enum → diagnostic + field omission (T4). |
| `opacity` | number 0..1 | no | |
| `transform` | gradient transform (§4.2) | no | Affine placement of the image content. |

### 4.2 Gradient transform

`linear-gradient` and `radial-gradient` fills (and image-fills) gain an optional
`transform` : the **6 finite floats** of an affine 2×3 matrix `[a, b, c, d, e, f]`,
rendered via SVG `gradientTransform`. It supersedes `angle_deg` when present.

- **Enforcement (T4)** : `transform` MUST be exactly 6 finite numbers ; each component
  is **clamped to a bounded range** by the compiler. A malformed transform (wrong
  arity, non-finite) is dropped — diagnostic, fall back to `angle_deg`. It is **never
  a free string** interpolated into SVG. `$defs/GradientTransform`.

```json
{ "kind": "image", "src": "https://cdn.example.com/tile.png",
  "objectFit": "cover", "transform": [1, 0, 0, 1, 12, 4] }
```

### 4.3 Per-fill `blendMode` (1.2+, #L)

`blendMode` (§2) is **per node**. A Figma node with **stacked fills** carries a blend
mode **per paint** ; §2 alone would drop every per-layer blend but the node's. **Each
`LSMLFill` variant** (`solid` / `linear-gradient` / `radial-gradient` / `image`) MAY
therefore carry its own optional `blendMode`, applied as a per-fill-layer
`mix-blend-mode` — **independent** of, and composed under, the node-level `blendMode`.

- **Type** : the same closed `BlendMode` enum as §2 — **no new value** is introduced.
- **Retro-compat** : a fill **without** `blendMode` renders `normal` (a pre-#L 1.2
  bundle is unchanged).
- **Enforcement (T4)** : a per-fill value outside the enum is rejected — diagnostic +
  omission, **never passthrough** ; double-gated by the compiler and the runtime, like
  the node blend. On a `shape` the per-fill blend lands on the layer's SVG paint
  element ; on a `frame` background it lowers to CSS `background-blend-mode` (one
  keyword per layer, same order). `blendMode` per variant in `$defs/Fill`.

```json
{ "kind": "shape", "geometry": "rect", "blendMode": "hard-light",
  "fills": [ { "kind": "solid", "color": "#f00", "blendMode": "multiply" },
             { "kind": "solid", "color": "#00f", "blendMode": "screen" } ] }
```

## 5. Asset URL gate (T1 + T2, normative for 1.2 asset sources)

Every URL that reaches the DOM through a 1.2 construct — an image-fill `src`, a
`mask.source.kind === "image"` `src` — MUST pass a **double-gate** (compiler at
lowering **and** runtime at render, because live LSDP deltas bypass the compiler).
The canonical predicate is `isHostAllowed(url, bundle.assets.allowedHosts)`
(`lumencast-js/packages/protocol/src/host-allow.ts`). `$defs/AssetUrl` in `schema.json`
is a coarse schema-level guard ; the normative gate is the predicate.

- **T2 — scheme allowlist.** Only `https:` (remote) **or** a bounded `data:image/*`
  base64 payload (`png|jpeg|jpg|gif|webp|avif|bmp|x-icon`) is admitted. `javascript:`,
  `data:text/*`, `data:text/html`, `data:image/svg+xml` (can carry script), `file:`,
  `blob:`, `vbscript:`, protocol-relative `//host`, and relative URLs are **rejected**.
- **T1 — host allowlist.** For an `https:` URL the parsed `new URL(url).hostname` MUST
  **equal-match** (case-insensitive, exact) an entry in `assets.allowedHosts`. Matching
  is on the **parsed hostname**, never a substring of the raw string. An empty / absent
  allowlist **denies every remote host** (deny-by-default). Embedded credentials
  (`user:pass@host`) are rejected outright.
- Rejection → diagnostic + omission of the asset, **never passthrough**. The diagnostic
  carries `{ nodeId, field, reason }` only — never the URL (Bastion R9).

> **Divergence from §11.1 (deliberate, noted).** The legacy §11.1 `allowedHosts`
> matching admits a `*.example.com` **wildcard**. The 1.2 asset gate is **stricter** :
> **exact hostname only, no wildcard**, per Bastion T1 ("strict `new URL().hostname`,
> not substring"). The two coexist : §11.1 governs 1.1 font / preload host matching ;
> §5 here governs 1.2 image-fill / mask-image sources. A future RFC SHOULD reconcile
> the two — flagged for the 1.2 freeze review.

## 6. Anti-drop & security invariants (ADR 001 carried into 1.2)

- Every 1.2 prop added is an entry in the compiler's consumed-key allowlist with an
  anti-drop diagnostic test (ADR 001 §3.4 / RC#7) — zero silent drop.
- Every value reaching CSS / SVG inline passes a strict parser with linear-time bounds
  (RC#10/#11/#12). The 1.2 parsers (`parseBlendMode`, `parseObjectFit`,
  `clampGradientTransform`, the typed `mask` lowering, `isHostAllowed`) reuse the
  `css-color.ts` / `filter-clamp.ts` discipline — closed allowlist, omit-on-miss,
  no value echoed.
- `emit_lsml.go` (Orion) PRESERVES `assets.allowedHosts` and spreads 1.2 props opaquely
  — it fabricates no value (Bastion T6).

[RFC 2119]: https://www.rfc-editor.org/rfc/rfc2119
