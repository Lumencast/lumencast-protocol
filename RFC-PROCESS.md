# RFC process

How protocol or schema changes are proposed, discussed, and accepted in Lumencast.

> Status: this process activates when the project transitions from BDFL to core team (per [GOVERNANCE.md](GOVERNANCE.md)). Until then, decisions happen in regular issues with the maintainer.

## When you need an RFC

You need an RFC for :

- Any change to the LSDP wire envelope or frame shape
- Any change to the LSML primitive catalog (new, modified, removed)
- Any change to the error code taxonomy
- Any change to reserved namespaces (`__inputs.*`, `__system.*`, `__test.*`, `__schema.*`)
- Any change to authentication / role semantics
- Any change to conformance criteria

You don't need an RFC for :

- Bug fixes
- Documentation improvements
- Adding examples or cookbook recipes
- SDK-specific changes (those go through normal PR review in the SDK repo)

When in doubt, open an issue first and ask.

## Process

### 1. Open an RFC issue

Title : `[RFC] <short title>`. Tag with `rfc:proposed`.

Body template :

```markdown
## Summary

One paragraph stating the change.

## Motivation

What is the problem ? Who is affected ? Real examples preferred over hypotheticals.

## Detailed design

The proposed change in full. Include :
- Spec text (markdown excerpts)
- Conformance fixture deltas
- Wire-format examples
- Migration path for existing implementations

## Drawbacks

What's the cost ? Who pays it ? Be honest about the trade-offs.

## Alternatives considered

What else was on the table ? Why was this proposal preferred ?

## Unresolved questions

What's still open ? What needs more discussion ?

## Compatibility impact

- Is this a breaking change ? (LSDP/2, LSML 2.0)
- Is this backward-compatible ? (LSDP/1.x, LSML 1.x)
- Migration required for existing servers/runtimes ?
```

### 2. Discussion period

Minimum 14 days from posting. Discussion happens in the issue.

The maintainer or core team identifies stakeholders : SDK maintainers (TS / Go / Rust / ...), runtime maintainers, known production adopters. They are explicitly tagged for input.

### 3. Triage

After 14 days, the maintainer or core team triages :

- **`rfc:accepted`** — proposal will be implemented. The proposer (or a volunteer) opens a PR.
- **`rfc:declined`** — proposal will not be implemented. The reasoning is documented in a closing comment, and an entry goes to [DECISIONS.md](DECISIONS.md).
- **`rfc:postponed`** — proposal is interesting but blocked on something else (another RFC, an upstream dependency, more data). The issue stays open with the `rfc:postponed` label.

A proposal can be triaged earlier than 14 days if discussion converges and the maintainer/core team agrees.

### 4. Implementation

For an accepted RFC :

- The PR updates the spec text + conformance fixtures + this DECISIONS.md
- The PR identifies which SDKs need updating (cross-link issues)
- The PR includes a migration note if breaking
- Merge requires :
  - At least one core-team approval
  - All affected SDKs identified
  - Backward-compat analysis in PR description

### 5. Versioning

- Backward-compatible additions → minor version (LSDP/1.0 → 1.1, LSML 1.0 → 1.1)
- Breaking changes → major version (LSDP/2, LSML 2.0)
- Each major lives for at least 12 months in parallel with its predecessor

## RFC numbering

Active RFCs are issues. Once accepted and merged, they receive a number and live in `spec/rfc/`. Format : `RFC-NNNN-short-name.md`.

The first RFC is `RFC-0001`. Numbers increment, never reuse.

## Withdrawing an RFC

The proposer may withdraw at any time before triage by closing the issue with a comment. Withdrawn RFCs do not count against future proposals — feel free to come back with a refined version.

## Forks of the spec

If the community fundamentally disagrees with a maintainer decision, they may fork. Forks must:

- Use a different name (not "Lumencast", per the brand policy)
- Clearly state the fork relationship
- Adapt the conformance suite to whatever divergence exists

This is healthy — competing ideas sharpen the canonical spec. We just need clean naming so users aren't confused.
