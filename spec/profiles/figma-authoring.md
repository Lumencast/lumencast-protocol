# Figma authoring profile — `x-figma.authoring/1`

> **Status** : v1, initial publication. Additive over LSML 1.1 ; declared via the `profiles[]` mechanism (LSML §17.3) and consumed via the `metadata.figma.*` escape hatch (LSML §17.4).
> **Identifier** : `x-figma.authoring/1`
> **Audience** : authoring tools that import / export LSML bundles produced by a Figma plugin, and renderers that want maximum visual fidelity to the original Figma design.
> **Generic pattern** : this profile is the canonical implementation of the **authoring profile** mechanism formalised in [LSML §17.5](../LSML-1.md#175-authoring-profiles). Every `metadata.figma.*` key listed below carries round-trip information per §17.5.1 (verbatim preservation, consistent float rounding, stable array order). Other vendors MAY model their authoring profile after this one — see §17.5.3 + the bottom-of-document "Adopting the profile from another vendor" section.

## Why a profile rather than spec extensions

LSML 1.1 is a portable, primitive scene format. Adding every Figma-specific property to the core spec would (a) bloat the schema for adopters that don't need them and (b) couple LSML's evolution to Figma's API.

This profile takes the opposite tack : everything Figma exposes that has no LSML 1.1 equivalent lives under `metadata.figma.*` per §17.4, and this document is the formal contract describing exactly which keys appear there, their types, and how a Figma-aware renderer SHOULD interpret them. Tools that don't speak this profile keep working — they ignore the metadata per §17.4 and render the underlying primitives best-effort.

## Profile declaration

A bundle authored by a Figma plugin SHOULD declare the profile at the top level :

```json
{
  "lsml": "1.1",
  "scene_id": "...",
  "scene_version": "sha256:...",
  "profiles": ["x-figma.authoring/1"],
  "layout": { ... }
}
```

A renderer MAY support a subset of the profile. Per LSML §17.3 the runtime MUST treat unknown profiles as no-ops — the bundle still validates structurally even when the renderer ignores `metadata.figma.*` entirely. Visual fidelity degrades gracefully :

| Renderer support | Behaviour |
|---|---|
| Full profile support | Reads every `metadata.figma.*` key per this doc, reproduces source visual 1:1. |
| Partial profile support | Reads the keys it knows, ignores the rest. |
| No profile support | Ignores all `metadata.figma.*` (existing §17.4 semantics). Bundle renders with native LSML primitives only — no shadows, no blend modes, no masks, no per-corner radii. |

## Field reference

All keys live under `<primitive>.metadata.figma.*` (per-primitive) unless explicitly noted otherwise. Keys are optional unless tagged **required**. A renderer that supports the profile MUST honour any key it understands.

### 1. Effects (drop shadow, inner shadow, layer / background blur)

```json
{
  "metadata": {
    "figma": {
      "effects": [
        {
          "type": "DROP_SHADOW",
          "visible": true,
          "color": { "r": 0, "g": 0, "b": 0, "a": 0.25 },
          "offset": { "x": 0, "y": 4 },
          "radius": 2,
          "spread": 0,
          "blendMode": "NORMAL"
        },
        {
          "type": "BACKGROUND_BLUR",
          "visible": true,
          "radius": 117.6
        }
      ]
    }
  }
}
```

**Effect type** is one of :
- `DROP_SHADOW` — keys : `color`, `offset {x,y}`, `radius`, `spread`, `blendMode`, `showShadowBehindNode` (bool, default `false`)
- `INNER_SHADOW` — same shape as `DROP_SHADOW`
- `LAYER_BLUR` — keys : `radius`
- `BACKGROUND_BLUR` — keys : `radius`

**Effect** common keys : `type` (required), `visible` (default `true`).

Renderers : apply effects in array order. `LAYER_BLUR` blurs the node ; `BACKGROUND_BLUR` blurs the content behind it (the parent's pixels) and shows through translucent fills.

### 2. Blend mode

```json
{ "metadata": { "figma": { "blendMode": "HARD_LIGHT" } } }
```

Values mirror Figma's `BlendMode` enum :
`PASS_THROUGH | NORMAL | DARKEN | MULTIPLY | LINEAR_BURN | COLOR_BURN | LIGHTEN | SCREEN | LINEAR_DODGE | COLOR_DODGE | OVERLAY | SOFT_LIGHT | HARD_LIGHT | DIFFERENCE | EXCLUSION | HUE | SATURATION | COLOR | LUMINOSITY`

Default : `PASS_THROUGH` for groups/frames, `NORMAL` for leaves. Renderers : compose the layer onto its parent using the named blend operator (CSS `mix-blend-mode` maps directly except for `PASS_THROUGH` which has no CSS equivalent — fall back to `NORMAL`).

### 3. Masks

```json
{ "metadata": { "figma": { "isMask": true, "maskType": "ALPHA" } } }
```

**`isMask`** : when `true`, the primitive acts as a mask for its sibling primitives drawn AFTER it (Figma masking convention : the mask shape is the FIRST visible child of a Mask group ; subsequent siblings are masked by it). Renderers : convert to CSS `mask-image` referencing the mask shape's rasterised silhouette.

**`maskType`** :
- `ALPHA` (default) — opacity of the mask shape determines visibility
- `LUMINANCE` — luminance of the mask shape
- `VECTOR` — path silhouette only, no anti-aliasing
- `OUTLINE` — stroke outline only

### 4. Per-corner radii + smoothing

```json
{ "metadata": { "figma": { "cornerRadii": [12, 12, 0, 0], "cornerSmoothing": 0.6 } } }
```

LSML `shape.cornerRadius` only carries a uniform radius. `cornerRadii` is the per-corner override `[topLeft, topRight, bottomRight, bottomLeft]` ; renderers apply it instead of the uniform value when present. `cornerSmoothing` 0..1 enables Apple-style squircles (CSS approximation : variable border-radius shape via `clip-path`).

### 5. Stroke details

```json
{
  "metadata": {
    "figma": {
      "strokeDetails": {
        "dashPattern": [8, 4],
        "strokeJoin": "ROUND",
        "strokeCap": "ROUND",
        "strokeMiterLimit": 4,
        "strokeAlign": "INSIDE",
        "strokeTopWeight": 1,
        "strokeRightWeight": 2,
        "strokeBottomWeight": 1,
        "strokeLeftWeight": 2
      }
    }
  }
}
```

LSML `stroke` carries only `color` + `width`. `strokeDetails` adds the dash pattern (`[on, off, on, off, ...]`), join/cap style, miter limit, alignment (`INSIDE | OUTSIDE | CENTER`), and per-side weights for asymmetric borders. All keys optional.

### 6. Constraints (resize behaviour)

```json
{ "metadata": { "figma": { "constraints": { "horizontal": "STRETCH", "vertical": "MIN" } } } }
```

Values per axis : `MIN | MAX | CENTER | STRETCH | SCALE`. Renderers that reflow on container resize use these to position children — equivalent to CSS pinning behaviour. Defaults `MIN/MIN`.

### 7. Layout overrides (auto-layout fine-grained control)

```json
{
  "metadata": {
    "figma": {
      "layoutAlign": "STRETCH",
      "layoutGrow": 1,
      "layoutPositioning": "ABSOLUTE",
      "minWidth": 200,
      "maxWidth": 600,
      "minHeight": null,
      "maxHeight": null
    }
  }
}
```

- `layoutAlign` : per-child override of the parent's counter-axis alignment. `MIN | CENTER | MAX | STRETCH | INHERIT` (default).
- `layoutGrow` : 0 (don't grow) or 1 (fill remaining axis). Equivalent to `flex-grow`.
- `layoutPositioning` : `AUTO` (managed by parent's auto-layout) or `ABSOLUTE` (escape auto-layout, position via `x/y`).
- `minWidth/maxWidth/minHeight/maxHeight` : numeric pixel constraints, `null` = unset.

### 8. Gradient stop positions

LSML `Fill.linear-gradient.stops[]` carries `{offset, color, opacity}`. Figma additionally exposes per-stop position with sub-percent precision and offset stops outside `[0, 1]` for clipped/tiled gradients. Capture the raw array when needed :

```json
{
  "metadata": {
    "figma": {
      "gradientStops": [
        [
          { "position": 0.177, "color": "#ff5700", "opacity": 1.0 },
          { "position": 0.840, "color": "#ff0900", "opacity": 1.0 }
        ]
      ]
    }
  }
}
```

The outer array is parallel-indexed with the primitive's `fills[]` (or `backgrounds[]` on a frame). Each entry is the verbatim stop list for that fill. When this key is present the renderer SHOULD use it instead of the LSML-side `stops[]`.

### 9. Gradient transform matrices

```json
{
  "metadata": {
    "figma": {
      "gradientTransforms": [
        [[0.589, 0.919, -0.267], [-0.760, 0, 0.880]]
      ]
    }
  }
}
```

Already widely used. Parallel-indexed with `fills[]` ; each entry is the Figma 2x3 affine matrix `[[m00,m01,m02],[m10,m11,m12]]` where the third column is the translation. Renderers should re-apply the matrix to reproduce the gradient handle exactly (LSML's `angle_deg` is lossy — drops translation/scale/shear).

### 10. Text extras

```json
{
  "metadata": {
    "figma": {
      "textCase": "SMALL_CAPS",
      "fontStyle": "Bold Italic",
      "textAutoResize": "WIDTH_AND_HEIGHT",
      "paragraphSpacing": 8,
      "paragraphIndent": 24,
      "textTruncation": "ENDING",
      "maxLines": 3,
      "hyperlinks": [
        { "range": [0, 5], "url": "https://example.com" }
      ]
    }
  }
}
```

- `textCase` : `SMALL_CAPS | SMALL_CAPS_FORCED` for cases LSML's `textTransform` can't represent. UPPER/LOWER/TITLE belong in `style.textTransform` per LSML §4.4.1.
- `fontStyle` : raw Figma `fontName.style` (e.g. `"Bold Italic"`, `"SemiBold"`). Used by importers to pick the closest installed font variant when the LSML `fontWeight + italic` mapping is ambiguous.
- `textAutoResize` : `NONE | WIDTH_AND_HEIGHT | HEIGHT | TRUNCATE`.
- `paragraphSpacing` / `paragraphIndent` : pixels.
- `textTruncation` : `DISABLED | ENDING`.
- `maxLines` : integer ; only meaningful when `textTruncation: "ENDING"`.
- `hyperlinks` : per-range URL annotations.

### 11. Frame extras

```json
{ "metadata": { "figma": { "clipsContent": false, "layerName": "Frame 7" } } }
```

- `clipsContent` : LSML 1.1 has a first-class `frame.clipsContent` (§4.3) ; the metadata key is kept for backward compatibility with v0.1 bundles. Readers SHOULD prefer the canonical field.
- `layerName` : the source Figma `node.name` verbatim, including any `[bind:...]` directive prefix. Importers restore it on re-import so the layer panel matches the source exactly.

### 12. Position fallback (legacy)

`metadata.figma.position` was used in pre-1.1.x bundles to carry per-leaf absolute position. LSML 1.1 promotes `position` to a universal prop (§5.4) ; the metadata key remains a fallback for v0.1 bundle compatibility. Readers SHOULD prefer the canonical universal `position`.

## Interpretation order

When more than one key would affect the same visual property, readers apply them in this order (later overrides earlier) :

1. LSML core primitive fields (`fill`, `cornerRadius`, `position`, `textTransform`, …).
2. `metadata.figma.*` legacy fallback keys (`position`, `clipsContent`, `textCase` for the 3 cases representable in `textTransform`).
3. `metadata.figma.*` profile-specific keys (`effects`, `blendMode`, `cornerRadii`, …).

Rationale : core fields are portable ; legacy fallbacks support older bundles ; profile-specific keys add Figma fidelity on top.

## Conformance — graceful ignore

A bundle declaring `profiles: ["x-figma.authoring/1"]` MUST also be valid against the core LSML 1.1 schema. A renderer that does not support the profile :

- MUST validate the bundle structurally (the `metadata.figma.*` block is allowed because `metadata` is open-ended per §17.4).
- MUST render using LSML primitives alone (no `effects`, no `blendMode`, no masks beyond what core supports).
- MUST NOT throw or surface an error solely because the profile is declared.

Authoring tools writing this profile :

- SHOULD emit canonical LSML fields whenever they exist (`position`, `clipsContent`, `textTransform`, `paths[]`, …).
- SHOULD only fall back to `metadata.figma.*` for values that have no canonical LSML representation.
- MAY emit redundant metadata copies as a transitional aid (e.g. `metadata.figma.position` parallel to the universal prop) ; readers prefer the canonical field per the interpretation order above.

## Round-trip stability

Two Figma plugins implementing this profile SHOULD produce byte-stable round-trip : `export(import(export(fig))) == export(fig)` after canonicalisation. Achieving this requires :

- All `metadata.figma.*` keys preserved verbatim across import → export.
- Float values rounded consistently (the canonicalizer's 3-decimal rounding applies).
- Arrays whose order matters (`effects[]`, `gradientStops[][]`, `gradientTransforms[]`, `cornerRadii[]`) preserve source order.

## Versioning

The profile identifier carries a major version : `x-figma.authoring/1`. Backward-incompatible changes bump the major (`/2`). Additive changes (new optional keys) keep the same identifier — readers MUST ignore unknown keys.

When the profile evolves :
- Keys MAY be added to existing categories ; readers fall back to the existing key when the new key is absent.
- Keys MUST NOT change semantics within a major. Renaming a key requires a new identifier.
- Deprecated keys remain documented for at least one major (parallel reads) before removal.

## Adopting the profile from another vendor

Other authoring tools (Sketch, Adobe XD, VSCode, …) MAY follow the same convention with their own namespace : `x-sketch.authoring/1`, `x-vscode.editor/1`, etc. The naming pattern is `x-<vendor>.<surface>/<major>` and each profile lives in `spec/profiles/<vendor>-<surface>.md` in the protocol repo (or in the vendor's own repo with a normative reference back here).

There is no central registry — profiles are discovered by their identifier in `bundle.profiles[]`.
