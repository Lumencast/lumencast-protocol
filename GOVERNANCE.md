# Governance

How decisions are made in Lumencast.

## Phases

Governance evolves with the project's maturity. Each phase has a clear next step that triggers transition.

### Phase 1 — BDFL (now)

A single maintainer ("benevolent dictator for life") owns the spec and merges PRs. All decisions are documented in [DECISIONS.md](DECISIONS.md) with rationale.

**Trigger to next phase**: 3 sustained external contributors with >5 merged PRs each, OR 6 months of project life — whichever comes first.

### Phase 2 — Core team (2-5 maintainers)

A core team of 2-5 maintainers shares ownership. Decisions by majority. The BDFL retains tie-breaking authority on protocol-level changes; the core team has full authority on SDKs, runtimes, tooling.

**Trigger to next phase**: protocol changes happen monthly OR community size exceeds 50 active contributors.

### Phase 3 — RFC process

Any breaking or semi-breaking spec change requires an RFC issue + 14-day public comment period + core team approval. Documented in [RFC-PROCESS.md](RFC-PROCESS.md) when this phase activates.

**Trigger to next phase**: legitimate corporate adopters request neutral governance.

### Phase 4 — Foundation (optional)

Donate the project to a neutral OSS foundation (Apache Software Foundation, OpenJS Foundation, CNCF, etc.). The maintainers serve as PMC.

This step is **optional** — many great projects stay in the core-team or RFC model indefinitely. Foundation makes sense only if neutrality unlocks specific corporate adoption.

## Decision categories

| Category | Authority | Process |
|---|---|---|
| Spec change (LSDP / LSML) | BDFL → core team → RFC | Issue + public discussion |
| New primitive in LSML | Major version (e.g. LSML 2.0) | RFC + reference implementation in canonical SDK |
| New error code | Minor version | Issue + PR |
| New SDK official inclusion | Core team review + conformance pass | PR to README + conformance check |
| Brand and naming | Maintainer + legal counsel | Trademark filings, conformance enforcement |
| Funding / commercial | Maintainer | Public disclosure if material |

## Architecture

Lumencast has six conceptual layers. Each layer can evolve at its own pace, but spec changes (Layers 1-2) are coordinated.

```
LAYER 1 — Wire protocol  (LSDP/1)            ← this repo
LAYER 2 — Display contract  (LSML 1.0)        ← this repo
LAYER 3 — Runtimes  (browser, native, ...)
LAYER 4 — Server SDKs  (TS, Go, Rust, ...)
LAYER 5 — Authoring tools  (visual editor, VS Code, ...)
LAYER 6 — Hosts adapters  (OBS, Stream Deck, iframe, ...)
```

Layers 3-6 are **federated** — anyone can build a runtime, SDK, or host adapter that passes conformance and call it Lumencast. Layers 1-2 are **centralized** — only this repo defines the wire format and schema.

## Brand

The "Lumencast" name and associated marks belong to the project's maintainer (or future foundation). Use is permitted for :

- Conformant SDKs that pass the conformance suite
- Educational, journalistic, and reference purposes
- Public discourse about the project

Use is not permitted for :

- Forks or competitors that present themselves as Lumencast
- Closed-source products that re-brand as Lumencast
- SDKs that fail conformance

Conformance enforcement is part of the brand promise — that's what makes Lumencast a useful name.

## Funding

The project accepts funding via:

| Channel | Purpose |
|---|---|
| GitHub Sponsors | Individual maintainer support |
| Open Collective (P3+) | Project-level expenses (domain, infra, conferences) |
| Sponsorship tiers (Bronze/Silver/Gold) | Corporate logo placement, no governance influence |

Funding does **not** purchase priority on the issue tracker, RFC outcomes, or roadmap influence. Spec decisions are technical and stay technical.

## Trademark

Once a name is chosen and verified clean, the maintainer files trademark in :

| Jurisdiction | Coverage |
|---|---|
| USPTO (US) | Class 9 (software) + Class 42 (technical services) |
| EUIPO (EU) | Same classes |

Cost ~$2k upfront. Reversal: trademark holder can transfer to foundation in Phase 4.

## Conflict resolution

Disputes between contributors that cannot be resolved through normal review:

1. **Discussion** — encouraged in the relevant issue or PR
2. **Mediation** — a maintainer mediates
3. **Decision** — BDFL or core-team majority decides
4. **Escalation** — if a contributor feels the decision violates the Code of Conduct, they can escalate per [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

The goal is always to keep moving the project forward. Perfect is the enemy of done.
