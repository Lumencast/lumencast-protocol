# Getting help

This repo holds **specs and conformance** — the source of truth that every Lumencast SDK and runtime is derived from. Where you ask for help depends on what you're trying to do.

## I'm using a Lumencast SDK and something is broken

Open an issue in **that SDK's repo** :

| SDK | Repo |
|---|---|
| TypeScript runtime + Node server | [`lumencast-js`](https://github.com/Lumencast/lumencast-js) |
| Go server + CLI | [`lumencast-go`](https://github.com/Lumencast/lumencast-go) |
| Rust SDK | [`lumencast-rs`](https://github.com/Lumencast/lumencast-rs) |
| Python SDK | [`lumencast-py`](https://github.com/Lumencast/lumencast-py) |

Bugs in the JS runtime go to `lumencast-js`, not here.

## I think the spec is wrong / unclear

That belongs here. Open a **bug report issue** with the area set to the relevant spec doc, or an **RFC issue** if you have a concrete proposal.

If a spec ambiguity is causing two SDKs to behave differently, that's the highest-priority kind of bug — file it here even if you found it via an SDK.

## I have a usage question

Open a **discussion** : <https://github.com/Lumencast/lumencast-protocol/discussions>

Don't open an issue for "how do I do X" — issues are for bugs and RFCs.

## I want to propose a new feature

Read [RFC-PROCESS.md](RFC-PROCESS.md) first. New protocol behaviours, new primitives, new error codes — all RFC-gated.

For *non-normative* additions (a new SDK in a new language, a new runtime targeting a new host, a new authoring tool) you don't need an RFC — just open the work in your own repo and link to it. Once it passes conformance and stabilizes, we add it to the official SDK list.

## I found a security issue

**Do not open a public issue.** Follow [SECURITY.md](SECURITY.md) — there's a reporting channel that gets you a 72-hour acknowledgement.

## I want to contribute

[CONTRIBUTING.md](CONTRIBUTING.md) is the entry point. The bar :

- Conformance must remain green after your change
- Normative changes require an RFC
- Code of conduct applies everywhere

## I'm trying to commercialize Lumencast

Apache 2.0 lets you do that. Build whatever you want on top.

If you fork or build a SaaS, please respect the brand : the **Lumencast** name and the LSDP/LSML acronyms are reserved for conformant implementations (see [GOVERNANCE.md § Brand](GOVERNANCE.md#brand)). Forks must use a different name.

## Where the maintainers are

- Issues / PRs / discussions : here on GitHub
- Real-time chat : not yet — we'll set up a Discord or Matrix when there's enough of a community to make it worthwhile

If you're an early adopter and want to help shape the project's direction, open a discussion saying so. Maintainer recruiting is in [GOVERNANCE.md § Phases](GOVERNANCE.md#phases).
