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
