# RFC-0001 — `x-zab.capture` : a transparent capture-placeholder primitive

- **Status** : accepted (`rfc:accepted`) — see **Amendment 1** (2026-06-23, `rfc:proposed`, re-validation Vigil pending)
- **Date** : 2026-06-23
- **Author** : Atlas (Zab vendor)
- **Affects** : LSML 1.1 primitive catalog (§4, §17.1), `@lumencast/compiler`, `@lumencast/runtime`, conformance suite
- **Supersedes** : —
- **Superseded by** : —

> ⚠️ **Amendment 1 (2026-06-23)** changes the runtime behaviour from *inert everywhere* to
> **context-aware** (ACQUIRE in capture-capable hosts, PLACEHOLDER otherwise). The
> "Runtime behaviour (normative)" block below is the ORIGINAL accepted text, kept for
> history; it is SUPERSEDED by Amendment 1 at the end of this document. Read Amendment 1
> for the binding behaviour.

> This RFC follows `RFC-PROCESS.md`. The change touches the LSML primitive catalog, so
> it requires an RFC rather than a plain PR. It is **additive** (LSML 1.1, no major bump)
> and **vendor-prefixed** (`x-zab.*` per §17.1) — it adds nothing to the *core* catalog
> and is invisible to non-Zab runtimes by the strict-fallback rule (§17.1.2).

## Summary

Introduce a vendor-prefixed LSML primitive `x-zab.capture` that reserves a rectangular
box in the scene tree and renders **nothing** (fully transparent) at runtime. It carries a
`sourceKind` (the class of live capture) and a logical `deviceRef` (a stable, hash-safe
device alias), but acquires **no** media stream. It is the in-band, content-addressed
anchor for live capture sources (webcam, screen, application audio, microphone) whose
*physical* resolution happens **outside** the bundle, per target (editor / preview /
on-air), in the consuming application.

## Motivation

Real, current production problem in the Zab broadcast stack:

- A Zab Canvas scene can contain a `source` component (`sourceKind: media.webcam |
  media.screen | media.app_audio | media.mic`). In the **canvas editor** it renders via
  `getUserMedia` and works.
- At bundle-export time (`Prism/.../lsml/from-scene.ts`, `serializeComponent`) the `source`
  component has **no LSML representation** → it emits `DROPPED_FIELD` and returns `null`.
  The component is silently dropped from the bundle.
- Therefore the **preview cockpit** and the **on-air** path (both render the *bundle* via
  the Lumencast runtime — preview in an Electron webview, on-air inside Pulsar/CEF) show
  **nothing** where the capture should be. The source only ever works in the editor.

Two facts are settled by prior Zab investigation and are **not** re-litigated here; they
are the constraints this RFC is shaped around:

1. **On-air `getUserMedia` is dead.** Pulsar's CEF fork (OBS-browser) ships no
   `OnRequestMediaAccessPermission` override and no `enable-media-stream` /
   `use-fake-ui-for-media-stream` command-line switch, so the page rendered inside Pulsar
   cannot acquire cam/mic/screen. A "Solar renderer that calls getUserMedia on-air" is
   physically impossible. On-air capture must come from Pulsar's **native** sources
   (`dshow_input`, `monitor_capture`/`window_capture`, `wasapi_input_capture`,
   `wasapi_process_output_capture`), composited by the consuming app.
2. **The bundle is content-addressed and shared.** Baking a physical `device_id` /
   `capture_source_id` into the bundle would (a) break content-addressing (the same logical
   scene would hash differently per machine) and (b) leak machine-local identity into a
   shared artifact. Device identity therefore must **not** live in the bundle.

The format's job is to express *"a transparent box of class X, logically named Y, lives
here."* It is **not** the format's job to acquire a stream. That separation is exactly what
`x-zab.capture` encodes.

## Detailed design

### Why a vendor primitive, not a core primitive

§4 closes the catalog at 9 primitives and forbids new core `kind` values without an LSML
major bump (§4, line "MUST NOT add `kind` values outside this set unless they prefix them
with `x-<vendor>.`"). §17.1 explicitly provides the additive, 1.1-compatible escape:
vendor-prefixed primitive `kind` values, with `x-zab.live-graph` already used as a worked
example (§17.1, the example block). Capture is a Zab-stack concern (it only makes sense in
front of a native compositor like Pulsar); standardizing it in the core catalog would force
LSML 2.0 on the whole ecosystem for a single vendor's need. `x-zab.capture` is the correct
mechanism and requires **no** major bump.

### Spec text (proposed addition to §17.1, as a worked normative example)

> **`x-zab.capture` — transparent capture placeholder (Zab vendor primitive).**
>
> ```json
> {
>   "kind": "x-zab.capture",
>   "x-zab.sourceKind": "media.webcam",
>   "x-zab.deviceRef": "primary-cam",
>   "size": { "w": 640, "h": 360 },
>   "opacity": 1.0
> }
> ```
>
> | Prop | Type | Required | Description |
> |---|---|---|---|
> | `x-zab.sourceKind` | enum: `media.webcam` \| `media.screen` \| `media.window` \| `media.app_audio` \| `media.mic` | yes | The class of live capture this box stands for. |
> | `x-zab.deviceRef` | string matching `[a-z][a-z0-9-]*`, 1..64 chars | yes | A **logical** device alias (e.g. `primary-cam`, `main-display`). Stable, machine-independent, **part of the content hash**. NEVER a physical `device_id`. |
> | `size` | `{ w, h }` | yes (visual kinds) | Box geometry. Required for visual `sourceKind`s (`media.webcam`/`media.screen`/`media.window`); audio-only kinds (`media.app_audio`/`media.mic`) MAY omit it (zero-area box). |
> | universal props | `visible`, `sizing`, `opacity`, `rotation` | no | Standard universal props (§5) apply to the placeholder box, NOT to any acquired stream (there is none). |
>
> **Runtime behaviour (normative).** A runtime that recognizes `x-zab.capture`:
> 1. MUST reserve the box per `size` + universal props + the surrounding layout, exactly as
>    it would for an `image` of the same geometry, so that downstream layout (siblings,
>    masks, stacks, grids) is unaffected.
> 2. MUST render the box **fully transparent** (no pixels, no element with visible paint).
>    It MUST NOT call `getUserMedia`, open a `MediaStream`, embed `<video>`/`<audio>`, or
>    reach any device. The placeholder is inert by definition.
> 3. MUST NOT emit a diagnostic for the *absence* of a stream — absence is the contract,
>    not an error.
> 4. MUST ignore `x-zab.deviceRef` for rendering purposes — it is metadata for the
>    consuming application's out-of-band resolver, never a runtime input.
>
> A runtime that does NOT recognize `x-zab.capture` follows §17.1.2 strict fallback and
> emits `BUNDLE_INCOMPATIBLE`.

### The frontier (normative boundary)

The RFC draws a hard line, restated so no future contributor erodes it:

- **Inside the bundle / inside Lumencast** : geometry, `x-zab.sourceKind`, logical
  `x-zab.deviceRef`, transparent rendering. Nothing else. Lumencast never acquires, never
  composites, never resolves a device.
- **Outside the bundle / inside the consuming app (Zab: Prism main process)** : the
  `deviceRef → physical device` mapping (a machine-local table, per operator machine) and
  the actual acquisition, per target:
  - **Editor / preview** (Solar in an Electron webview, where `getUserMedia` is granted):
    `getUserMedia({ deviceId })` resolved from `deviceRef`.
  - **On-air** (Pulsar/CEF, where `getUserMedia` is dead): a **native** Pulsar source
    (`dshow_input` etc.) anchored to the placeholder's on-screen rectangle, driven by the
    app over its existing Pulsar control channel.

The placeholder's geometry is what lets the consuming app position the native source over
the exact box the author drew. Same `deviceRef`, two physical resolutions, one bundle.

### Conformance fixture deltas

Add to `conformance/lsmlz` (or the appropriate LSML primitive suite):

- `valid/x-zab-capture-renders-transparent.yaml` — a bundle with one `x-zab.capture` node;
  expected render = an empty box of the declared geometry, zero painted pixels, no console
  diagnostic, no network/device access.
- `valid/x-zab-capture-audio-no-size.yaml` — `sourceKind: media.mic` with `size` omitted;
  expected = valid, zero-area inert node.
- `invalid/x-zab-capture-bare-device-id.yaml` — a `deviceRef` that looks like a physical id
  (contains `:` or a UUID) → rejected by the `[a-z][a-z0-9-]*` pattern (`INVALID_VALUE`).
- `invalid/x-zab-capture-unknown-runtime.yaml` — fed to a runtime without the Zab plugin →
  expected `BUNDLE_INCOMPATIBLE` (exercises §17.1.2).

### `profiles[]` declaration

A bundle using `x-zab.capture` SHOULD declare `"x-zab.capture/1"` in `profiles[]` (§17.3)
so the dependency on the Zab runtime plugin is machine-readable. Runtimes shipping the
plugin publish `x-zab.capture/1` in their supported-profile list.

## Drawbacks

- **Non-portable bundles.** Any bundle containing `x-zab.capture` requires a Zab-plugin
  runtime; a vanilla Lumencast runtime rejects the whole bundle (§17.1.2, by design — strict
  fallback, not silent skip). This is the price of any vendor primitive and is acceptable:
  Zab capture scenes are only ever consumed by the Zab runtime (Solar's vendored runtime).
- **Spec carries a vendor example.** The core spec gains a normative example for a
  vendor-prefixed primitive. This is consistent with §17.1 already naming `x-zab.live-graph`,
  and documents the canonical pattern for *placeholder* vendor primitives generally.
- **Geometry duplication risk.** The placeholder geometry and the native-source rectangle
  are maintained in two systems (Lumencast box vs Pulsar source transform). They can drift.
  Mitigation: the consuming app derives the native-source transform *from* the placeholder's
  resolved layout box, not independently — this is an app contract, out of scope for the
  format, but called out so the boundary is not misimplemented.

## Alternatives considered

1. **Make `media` carry a live-capture mode (`media_kind: "capture"`).** Rejected:
   `media` binds a URL (`bind.src`) and renders `<video src>`; capture has no URL and must
   render *nothing*. Overloading `media` would muddy a stable core primitive and still
   require a behavioural fork on every runtime.
2. **A new *core* primitive `capture`.** Rejected: forces LSML 2.0 (§4 closure) on the whole
   ecosystem for a single vendor's, compositor-specific need. §17.1 exists precisely to
   avoid this.
3. **Bake the device into the bundle (`device_id`).** Rejected: breaks content-addressing
   and leaks machine-local identity into a shared artifact (Motivation fact 2).
4. **Keep dropping `source` and let the app inject a native source positioned by some
   side-channel coordinate list.** Rejected: the geometry/identity then live *outside* the
   authored scene, so the author loses authority over placement and the editor/preview/on-air
   renders diverge. The placeholder keeps geometry authoritative and in-hash.
5. **`metadata.<vendor>` escape hatch (§17.4) on a `frame`.** Rejected: `metadata` is for
   non-rendered annotations; here we need a node that *reserves layout* and is *strictly*
   rejected by non-Zab runtimes (not silently rendered as an empty frame). Only a
   vendor-prefixed *primitive* gives both.

## Unresolved questions

1. **Strict-fallback gap in the reference runtime.** `@lumencast/runtime`'s `tree.tsx`
   currently emits a non-fatal diagnostic (`"unknown render kind ; node not rendered"`) and
   continues, rather than emitting `BUNDLE_INCOMPATIBLE` as §17.1.2 mandates. The reference
   runtime is therefore already non-conformant on this point, independent of this RFC.
   Should this RFC also tighten that path, or is it a separate conformance fix? Proposed:
   the implementing ADR (lumencast-js ADR 004) registers `x-zab.capture` so the Zab runtime
   *recognizes* it (no fallback hit on the happy path); the generic strict-fallback fix is
   tracked separately as a conformance bug.
2. **Should `deviceRef` carry an optional human label** (e.g. `"Front camera"`) for operator
   UIs? Proposed: no — label is an app-local concern keyed by `deviceRef`, out of the hash.
3. **`media.window` vs `media.screen`** — keep both as distinct `sourceKind`s (window vs
   full-display capture) or collapse to one and let the app pick? Proposed: keep both; the
   author's intent (a single window vs a whole display) is meaningful and should be in-hash.

## Compatibility impact

- **Breaking?** No. Additive, LSML 1.1, vendor-prefixed (§17.1).
- **Backward-compatible?** Yes for the format version (still `lsml: "1.1"`). Bundles using
  the primitive are non-portable to non-Zab runtimes **by design** (§17.1.2).
- **Migration for existing servers/runtimes?** None required for non-Zab runtimes. The Zab
  runtime (Solar's vendored `@lumencast/runtime`) must ship the `x-zab.capture` plugin
  (lumencast-js ADR 004) before any bundle uses the kind. No existing bundle contains the
  kind today (the `source` component is currently dropped), so there is no data migration.

---

## Amendment 1 — context-aware runtime (ACQUIRE / PLACEHOLDER)

- **Date** : 2026-06-23
- **Status** : `rfc:accepted`
- **Author** : Atlas
- **Supersedes** : the "Runtime behaviour (normative)" block in §Detailed design (the
  *inert-everywhere* rule). The kind shape, `deviceRef` hash-safety, the frontier, profiles,
  strict-fallback (§17.1.2) and compatibility are UNCHANGED.

### A1.1 Motivation

The accepted *inert-everywhere* rule produces a correct ON-AIR result (Pulsar composites a
native source behind the transparent box) but a BROKEN PREVIEW result: the cockpit preview
renders the scene solely through a Solar webview of the bundle (no editor React tree, no
`use-live-source` getUserMedia in that path), so a "Full · Camera" scene shows an EMPTY
SCREEN — the placeholder is transparent and nothing composites a stream behind it in the
webview. The placeholder must therefore *acquire* the stream itself when — and only when —
its host can.

### A1.2 Binding runtime behaviour (replaces the original block)

A runtime that recognizes `x-zab.capture`:

1. MUST reserve the box per `size` + universal props + surrounding layout, exactly as an
   `image` of the same geometry, in BOTH modes below.
2. MUST select a mode by **capability detection at mount** (feature/permission detection,
   NOT an environment flag): capture-capable iff `navigator.mediaDevices?.getUserMedia`
   exists AND media-capture is usable in the current context.
   - **(a) ACQUIRE mode** (capable host — e.g. the Electron preview webview with
     auto-granted media permissions): the runtime MAY acquire a live stream via
     `getUserMedia` (webcam/mic) or `getDisplayMedia` (screen/window) per
     `x-zab.sourceKind` and render it in the box (`<video>` for visual kinds; audio kinds
     stay visually empty). The physical device is resolved from `x-zab.deviceRef` through a
     **host-provided resolver** (§A1.3) — never a bundle-baked id. On any failure (no
     resolver, no device, permission denied, acquisition error) the runtime MUST fall back
     to PLACEHOLDER mode WITHOUT throwing or blanking the surrounding tree.
   - **(b) PLACEHOLDER mode** (non-capable host — e.g. CEF/Pulsar on-air): renders the box
     **fully transparent**, acquires nothing, reaches no device. The consuming app
     composites a native source behind it (ON-AIR PATH UNCHANGED).
3. MUST NOT emit a diagnostic for being in PLACEHOLDER mode or for an ACQUIRE→PLACEHOLDER
   fallback — a stream-less box is a valid mode, not an error.
4. MUST NOT treat `x-zab.deviceRef` as a physical id. In ACQUIRE mode it passes the LOGICAL
   `deviceRef` to the host resolver; the resolution result (a `deviceId`) is used only as a
   live `getUserMedia` constraint and NEVER enters the bundle or the content hash.

### A1.3 Host-provided device resolver (the `deviceRef → deviceId` boundary)

The bundle stays content-addressed: it carries only the LOGICAL `x-zab.deviceRef`. The
physical `deviceRef → deviceId` mapping lives in the consuming app, per operator machine,
OUTSIDE the bundle. To bridge the two without baking identity into the bundle and without an
in-runtime device table, the runtime exposes an OPTIONAL injection point:

- The consuming app MAY supply a resolver `resolveCaptureDevice(deviceRef, sourceKind) →
  { deviceId?: string } | null`, provided to the runtime at mount via host config (a
  constructor/option field), NOT via the bundle and NOT via the LSDP wire.
- If a resolver is supplied: ACQUIRE mode calls it and uses the returned `deviceId` as a
  `getUserMedia({ video|audio: { deviceId } })` constraint.
- If NO resolver is supplied OR it returns `null`: ACQUIRE mode MAY call `getUserMedia` with
  DEFAULT constraints (no `deviceId` — the host's default device), or fall back to
  PLACEHOLDER. The SDK ADR picks the default; this RFC requires only that the absence of a
  resolver never throws.

This keeps Lumencast device-agnostic (it owns no mapping), keeps the bundle hash clean (only
the logical ref is in-hash), and lets each consuming app decide how it discovers the
`deviceId` (in Zab: injected into the Solar webview bootstrap main-side — see ADR 004 / the
Prism issue, an app concern, not a format concern).

### A1.4 Unchanged

Kind shape & props, `deviceRef` regex & hash membership, the frontier (Lumencast renders /
the app resolves & — on-air — composites natively), `profiles[]` (`x-zab.capture/1`),
strict-fallback §17.1.2, and all compatibility claims are UNCHANGED by this amendment.
