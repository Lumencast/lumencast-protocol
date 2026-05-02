# Contributing to Lumencast

Thanks for considering a contribution. Lumencast aims to become a **standard** — that means we hold the bar high on consistency, conformance, and clarity. This guide describes how to contribute productively.

## Table of contents

- [Where Lumencast lives](#where-lumencast-lives)
- [Filing issues](#filing-issues)
- [Proposing protocol or schema changes](#proposing-protocol-or-schema-changes)
- [Implementing a new SDK](#implementing-a-new-sdk)
- [Implementing a new runtime](#implementing-a-new-runtime)
- [Conformance](#conformance)
- [Coding conventions](#coding-conventions)
- [Commit & PR flow](#commit--pr-flow)
- [Code of conduct](#code-of-conduct)

## Where Lumencast lives

Lumencast is a multi-repo project under the `lumencast` GitHub organization.

| Repo | Purpose |
|---|---|
| `lumencast-protocol` (this) | LSDP/1 + LSML 1.0 specs, conformance fixtures, error taxonomy. **Source of truth.** |
| `lumencast-js` | TypeScript runtime + Node server SDK monorepo |
| `lumencast-go` | Go server SDK + `lumencast` CLI binary |
| `lumencast-rs` | Rust SDK |
| `lumencast-py` | Python SDK |
| (more) | Future runtimes / SDKs |

Spec changes happen here. SDK fixes happen in the relevant SDK repo.

## Filing issues

- **Bug** in a specific SDK → file in that SDK's repo.
- **Bug or ambiguity** in the spec → file here.
- **Feature request** for a primitive, error code, or protocol behavior → file here as an RFC issue (see below).
- **Security issue** → see [SECURITY.md](SECURITY.md). Do not file publicly.

A good issue includes:
- The version of the spec / SDK you are using
- A minimal reproduction
- The expected vs actual behavior
- Conformance fixture if relevant

## Proposing protocol or schema changes

LSDP and LSML changes follow a lightweight RFC process to keep the spec auditable.

1. Open an issue tagged `rfc:proposed`. Describe the problem first, the proposal second, and the alternatives considered.
2. Discussion happens in the issue. Community + maintainers weigh in.
3. If consensus emerges, a maintainer tags it `rfc:accepted`. The proposer (or a volunteer) opens a PR with the spec change + conformance fixtures.
4. Merge requires :
   - Approval from at least one maintainer
   - All affected SDKs identified (issue cross-links)
   - Backward compatibility analysis documented in the PR description
5. After merge, SDKs implement the change. The first one to land becomes the reference for subsequent ones.

Breaking changes are reserved for major version bumps (LSDP/1 → LSDP/2, LSML 1.0 → LSML 2.0). Minor versions add backward-compatible features.

## Implementing a new SDK

We welcome SDKs in any language. The bar :

- **Conformance**: must pass the conformance suite (see [conformance/README.md](conformance/README.md)).
- **API parity**: matches the canonical `mount(options): handle` shape (browser runtime) or `Server { compose, emit }` shape (server SDK), translated idiomatically to the target language.
- **Documentation**: README with quickstart + API reference.
- **Testing**: unit tests covering protocol decoding, error handling, reconnect.
- **License**: Apache 2.0 (matches the org).

Once you have a working implementation, open an issue here proposing addition to the official SDK list. We'll review for consistency and add it to the README.

## Implementing a new runtime

A runtime renders LSML scenes for a specific target (browser, native mobile, terminal, etc.). The bar :

- **Primitive parity**: implements all 8 LSML primitives (`stack`, `grid`, `frame`, `text`, `image`, `shape`, `media`, `repeat`) faithfully.
- **Animation discipline**: only `transform` / `opacity` / `filter` animatable, GPU-only.
- **Mode tree-shaking**: implements broadcast / control / test mode separation, ideally at build time.
- **Protocol conformance**: passes LSDP/1 conformance fixtures end-to-end.
- **Performance**: meets budgets in [PERFORMANCE.md](spec/PERFORMANCE.md) (delta → render p95 ≤ 50ms on target hardware).

## Conformance

Every contribution that touches the protocol or schema must update the conformance suite. The suite is :

- **Language-agnostic** — fixtures are bytes + YAML scenarios.
- **Versioned** — `conformance/v1/` for LSDP/1 + LSML 1.0, future versions add directories.
- **Mandatory** — a SDK or runtime that does not pass conformance is not allowed to use the Lumencast name (see [GOVERNANCE.md](GOVERNANCE.md#brand)).

Run conformance on your SDK :

```sh
lumencast conformance --server <your-server-url>
```

(Once `lumencast-go` ships the CLI.)

## Coding conventions

This repo holds specs, not code. But for SDK repos :

| Aspect | Convention |
|---|---|
| Public API | Match the canonical surface defined in [spec/RUNTIME-API.md](spec/RUNTIME-API.md) translated idiomatically |
| Naming | Snake_case in JSON wire (matches LSML), language-native everywhere else |
| Errors | Match the error code taxonomy in [spec/ERROR-CODES.md](spec/ERROR-CODES.md) |
| Versioning | Independent semver per SDK; compatibility matrix published in each SDK's README |

## Commit & PR flow

- One PR per logical change. No "fix stuff" or "wip" commits.
- Commits in English, format `type: description` (e.g. `spec(lsdp): clarify reconnect schedule on auth failure`).
- PRs target `main`. Squash merge.
- Each PR includes :
  - What changed
  - Why (link to issue / RFC)
  - Conformance impact
  - Backward compat impact

## Code of conduct

All interactions in this project are governed by the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Violations can be reported via the channels described there.

---

Thanks for being part of building this. Lumencast is small enough today that contributors can shape its direction meaningfully — we mean it.
