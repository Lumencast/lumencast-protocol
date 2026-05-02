<!--
Thanks for the PR. Please fill in the sections below — short and direct
is fine, no need to pad.
-->

## Summary

<!-- One paragraph: what changed, why. -->

## Type of change

- [ ] Bug fix (no behaviour change to a passing implementation)
- [ ] Spec / schema editorial fix (typo, clarification, no normative change)
- [ ] Spec / schema normative change (LSDP/LSML/error taxonomy/conformance)
- [ ] Conformance suite addition (new scenario, new fixture)
- [ ] Documentation
- [ ] CI / tooling
- [ ] Governance

## Linked issue / RFC

<!--
For normative changes, link to the RFC issue. RFCs accept after at least
14 days of public discussion (see RFC-PROCESS.md).
-->

Closes #

## Compatibility impact

- [ ] Backward-compatible (no version bump, or minor)
- [ ] Breaking (requires major version bump)
- [ ] N/A (editorial / docs / CI only)

## Conformance suite impact

- [ ] No conformance change
- [ ] New scenario added (referenced in `manifest.json`)
- [ ] Existing scenario or fixture modified (explained below)
- [ ] Error code added / changed (also updates `ERROR-CODES.md`)

<!-- If you touched conformance, summarize the diff in 1-2 sentences. -->

## Affected SDKs

<!--
For normative changes — which sibling repos will need to land matching
PRs ? Cross-link the issues you opened in those repos.
-->

- [ ] `lumencast-js`
- [ ] `lumencast-go`
- [ ] `lumencast-rs`
- [ ] `lumencast-py`
- [ ] None (this PR is spec-only)

## Test plan

<!--
For schema / fixture changes : did `validate-bundle.py` succeed locally ?
For conformance scenarios : does the YAML parse, does manifest.json index it ?
For prose changes : did `markdownlint-cli2` and the link checker pass locally ?
-->

- [ ] `python scripts/validate-bundle.py spec/examples/*.lsml.json` passes
- [ ] CI is green on this PR

## Reviewer checklist

<!-- Reviewer fills in. -->

- [ ] Spec text reads cleanly (no ambiguity, no contradiction with adjacent sections)
- [ ] Conformance fixtures / scenarios match the spec change
- [ ] Affected SDKs are notified
- [ ] DECISIONS.md updated for non-trivial design choices
