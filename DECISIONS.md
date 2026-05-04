# Decisions log

A running list of design decisions made for the Lumencast specs. Each entry has a date, the question being answered, the answer, and the reasoning. New entries append to the bottom.

This is not normative — the specs themselves (LSDP/1, LSML 1.0) are normative. This log captures *why* the specs are the way they are, for future contributors.

---

## 2026-05-03 — Closed primitive catalog

**Question** : should LSML allow user-defined primitives (custom React/Vue components, etc.) ?

**Answer** : no. LSML 1.0 ships exactly 8 primitives (stack, grid, frame, text, image, shape, media, repeat). Adding a primitive requires LSML 2.0.

**Reasoning** :
- Sécurité par construction — pas de surface XSS via custom components.
- Bundle size garanti — aucune scène ne peut faire grossir le runtime.
- API stability — un schéma d'aujourd'hui est lisible dans 10 ans.
- L'extensibilité user vit ailleurs : compositions de primitives ("user components"), inlinées dans le bundle, pas dans le runtime.

The trade-off : authors of complex visualizations (charts, force graphs, 3D scenes) cannot add primitives. They must compose existing primitives, or wait for a major bump that adds a `webgl` primitive.

---

## 2026-05-03 — Leaf-grain push (no full-state replace)

**Question** : should LSDP allow full-state replace as an optimization for "everything changed" ?

**Answer** : no. LSDP transports `snapshot` (initial state) and `delta` (incremental). Reconnect after gap re-emits `snapshot`. There is no "full replace" frame.

**Reasoning** :
- Two frame types are easier to validate than three.
- "Everything changed" is rare in practice ; when it does happen, `scene_changed` triggers a fresh subscription, which produces a fresh `snapshot` — same effect, cleaner semantics.
- Servers that push full-state every tick are bypassing the design intent. Surface this as user error, not protocol affordance.

---

## 2026-05-03 — Content-addressed scene bundle

**Question** : should the scene bundle be addressed by version number (`v1.2.3`) or by content hash ?

**Answer** : content hash (sha256). The `scene_version` is `sha256:abc...`.

**Reasoning** :
- Cache forever without invalidation logic.
- Multiple versions co-exist transparently — different clients can be on different versions during a rollout.
- Rollback is just switching which version is active ; the old bundle is still cached at its hash.
- Hash mismatch on fetch is a hard error (`BUNDLE_FETCH_FAILED`), surfaces tampering.

The cost : human-readable version numbers must be tracked separately (e.g. in the bundle metadata or a release tag). This is acceptable.

---

## 2026-05-03 — GPU-only animation

**Question** : should LSML allow animating any CSS property ?

**Answer** : no. Only `transform`, `opacity`, `filter` are animatable.

**Reasoning** :
- Animations on `width` / `height` / `top` / `left` trigger DOM reflow.
- Reflow during a broadcast is visually janky and uses orders of magnitude more CPU.
- The runtime contract guarantees 0 layout events during the animation hot path. To enforce this in user-authored content, the schema constrains what can be animated.
- Authors who need to animate dimensions can use scale/translate transforms — which are GPU-composited equivalents.

---

## 2026-05-03 — Multi-language SDK strategy : TS + Go canonical

**Question** : which language is the reference server SDK ?

**Answer** : Go for the canonical reference + CLI ; TypeScript for the Node-side server SDK ; Rust and Python in wave 2 ; Elixir / Kotlin / .NET in community waves.

**Reasoning** :
- Go fits the workload (concurrency, single binary, WS first-class) and has the production validation from Orion v2 that prefigured Lumencast.
- TS is mandatory for the browser runtime ; having a Node SDK in the same monorepo lets a TS-only adopter ship without leaving the language.
- Rust and Python serve adjacent audiences (high-performance / data science) without competing with the Go reference.
- Conformance suite is language-agnostic — every SDK proves itself the same way.

---

## 2026-05-03 — License : Apache 2.0

**Question** : MIT, Apache 2, or AGPL ?

**Answer** : Apache 2.0.

**Reasoning** :
- MIT lacks the patent grant that protects corporate adopters.
- AGPL would block adoption by FAANG-class companies (their internal policies forbid it).
- Apache 2 strikes the balance : free adoption, patent grant, trademark preserved separately.
- Future commercial offering (Lumencast Cloud) is allowed via Open Core ; OSS spec stays Apache 2.

---

## 2026-05-03 — LSML 1.x authoring fidelity (universal `position`, `paths[]`, `clipsContent`)

**Question** : when an authoring tool (Figma plugin, Sketch plugin, …) needs to round-trip per-leaf absolute position, multi-subpath geometry with winding rule, and frame clipping, should those live in `metadata.figma.*` (escape hatch §17.4) or be promoted to first-class spec fields ?

**Answer** : promote, additively. LSML 1.1 gains :
- `position` as a universal prop on every primitive (was frame/image-only).
- `shape.paths[]` array as an alternative to `pathData` for multi-subpath geometry with per-subpath `windingRule` (`NONZERO` | `EVENODD`).
- `frame.clipsContent` boolean (default `true`).
- Cookbook clarification (§4.4.1) that authoring tools should map their native `textCase`/`textTransform` field to the existing `style.textTransform` rather than to `metadata.*`.

**Reasoning** :
- Absolute layout is universal across visual authoring tools (Figma, Sketch, XD, Penpot, Photoshop) — not a Figma quirk. It belongs in core, not in a vendor escape hatch.
- Multi-subpath geometry is the standard output of any boolean-operation flatten. A single `pathData` string forces authoring tools to either drop subpaths (visually broken) or concatenate them with the wrong winding (visually wrong).
- `metadata.figma.*` was actively used by `lumencast-figma` v0.1 and demonstrated the gap. Keeping it as the workaround makes bundles non-portable across SDKs that won't honour Figma-specific metadata.
- All three additions are backward-compatible. 1.0 receivers ignore them. 1.1.0 receivers without the change ignore them too — visual fidelity degrades gracefully, no breakage.

**Trade-offs** :
- Schema surface grows by ~5 optional fields. Acceptable cost for the fidelity payoff.
- `pathData` and `paths` create two ways to express the single-path case. The shorthand pays for itself in compact bundle output and 1.0 back-compat.
- Authoring tools that already wrote `metadata.figma.*` need a migration. Soft transition : 1.1.x readers SHOULD honour the metadata as a fallback ; hard removal at 2.0.

Cross-link : RFC issue + spec PR on `lumencast-protocol`. Conformance fixtures `bundle-universal-position-validates`, `bundle-shape-multipath-validates`, `bundle-frame-clipscontent-validates` (all `recommended`).

---

## 2026-05-04 — Authoring profiles for vendor-specific data

**Question** : authoring tools (Figma plugin, Sketch plugin, VSCode editor extension, …) need to round-trip a host of properties LSML 1.1 doesn't represent natively (effects, blend modes, masks, per-corner radii, gradient stop positions, layout overrides, …). Should each missing property become a spec-level field, or should we formalise a different mechanism ?

**Answer** : neither. Introduce a category of *authoring profiles* that pair a `profiles[]` declaration with a `metadata.<vendor>.*` block, both already valid LSML 1.1 (§17.3 + §17.4). The first instance is `x-figma.authoring/1`, documented at `spec/profiles/figma-authoring.md`.

Two profile flavours, distinguished by version-suffix syntax :
- **Rendering profiles** (`<vendor>.<name>-<version>`, dash) — hard requirements that change rendering. Unsupported = `BUNDLE_INCOMPATIBLE`.
- **Authoring profiles** (`<vendor>.<name>/<major>`, slash) — soft hints that the bundle carries vendor-specific data under `metadata.<vendor>.*`. Unsupported = silently ignored, falling back to LSML primitives only.

The schema also gains per-primitive `metadata` (§17.4.1) so each leaf can carry its own vendor block.

**Reasoning** :
- LSML core stays minimal and portable. No bloat for adopters that don't author through Figma.
- Vendor extensions evolve independently of the core. New Figma fidelity features ship as additions to `x-figma.authoring/1` without an LSML-level RFC.
- Renderers compose : a Figma-aware viewer reads the metadata for full fidelity ; a portable runtime reads the primitives and degrades gracefully.
- The pattern generalises : Sketch, Adobe XD, Penpot, VSCode's "scene preview" extension, etc. all get the same affordance with their own profile docs.

**Trade-offs** :
- Two flavours of profile (rendering vs authoring) add a learning curve. Mitigated by keeping the version-suffix syntax visually distinct (dash vs slash) and documenting the difference at §17.3.
- Per-primitive metadata makes the schema slightly more permissive (`additionalProperties` allowed under `metadata`). Acceptable cost for the authoring-tool ecosystem.
- Tools writing authoring profiles MUST resist the temptation to put rendering-critical data in metadata — anything that genuinely affects portable rendering still belongs in core LSML (and triggers an RFC).

Cross-link : `spec/profiles/figma-authoring.md`, conformance fixture `bundle-authoring-profile-ignored`. The figma plugin (`lumencast-figma`) is the reference implementation.

---

## Adding a decision

Open a PR appending an entry. Format :

```
## YYYY-MM-DD — Short title

**Question** : what was being decided.

**Answer** : the decision.

**Reasoning** : why. Bullet points. Cite trade-offs honestly.

---
```

Decisions never disappear. If a decision is reversed, append a new entry that references the old one and explains the reversal.
