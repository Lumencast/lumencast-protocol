# Lumencast cross-language interop tests

This directory hosts the **interop matrix** : every supported LSDP/1 server SDK is exercised by every supported harness, scenario by scenario. The intent is a single CI workflow that proves "language X server speaks the same protocol as language Y client" across the full conformance suite.

## Contents

| File | Purpose |
|---|---|
| [`CONTROL.md`](CONTROL.md) | Test control plane spec. Servers expose this HTTP API to be driven by external harnesses. |
| [`run-matrix.sh`](run-matrix.sh) | Bash driver that loops over (server, harness) pairs and reports per-scenario pass/fail. |
| [`fixtures/canonical-tokens.json`](fixtures/canonical-tokens.json) | Stable placeholder→value mapping used across every scenario in the matrix. |
| `MATRIX.md` (auto-generated) | Last-run report. Updated by CI on every push to `main`. |

The conformance scenarios themselves live in `../conformance/v1/scenarios/` and are shared with each SDK's own test suite.

## How the matrix runs

1. **Discover** — the driver expects four SDK checkouts as siblings of `lumencast-protocol/` (or paths overridden via `LUMENCAST_GO`, `LUMENCAST_JS`, `LUMENCAST_RS`, `LUMENCAST_PY` env vars).
2. **Build** — each SDK is built once, producing a binary or script entrypoint with `serve-scenario` and `conformance` subcommands.
3. **Run** — for each (server, harness) pair where `server != harness` (homogeneous runs are covered by each SDK's own CI) :
   1. Start `<server> serve-scenario --test-control-port <p1> --ws-port <p2>`
   2. Wait for the discovery line on stdout
   3. Run `<harness> conformance --server ws://... --control-url http://...`
   4. Tear down the server, capture exit codes
4. **Report** — pass/fail per scenario, written to `MATRIX.md`.

## Running locally

```sh
# From the lumencast-protocol checkout, with sibling SDKs :
cd interop
./run-matrix.sh
```

```sh
# Override SDK paths :
LUMENCAST_GO=$HOME/code/lumencast-go \
  LUMENCAST_JS=$HOME/code/lumencast-js \
  LUMENCAST_RS=$HOME/code/lumencast-rs \
  LUMENCAST_PY=$HOME/code/lumencast-py \
  ./run-matrix.sh
```

```sh
# Restrict to one pair :
./run-matrix.sh --server go --harness js
```

```sh
# Restrict to one scenario :
./run-matrix.sh --scenario subscribe-snapshot-delta
```

## Adding an SDK to the matrix

1. Implement the `serve-scenario` CLI subcommand per [`CONTROL.md`](CONTROL.md). It MUST :
   - Accept `--test-control-port` and `--ws-port` flags
   - Print a single discovery line on stdout (one JSON object) before listening
   - Expose the four `/test/*` endpoints as specified
2. Implement the `conformance` CLI subcommand to accept `--server` (WebSocket URL) and `--control-url` (HTTP URL of the test control plane).
3. Add the SDK's discovery wiring to `run-matrix.sh` under `_resolve_sdk()`.
4. Open a PR to `lumencast-protocol` adding the SDK to the matrix.

## Status as of v0.1

The control plane spec is published. The driver scaffold is in place. Currently :

| SDK | `serve-scenario` | `conformance --control-url` | In matrix |
|---|---|---|---|
| lumencast-go | YES | YES | YES |
| lumencast-js | YES | YES | YES |
| lumencast-rs | YES | YES | YES |
| lumencast-py | YES | YES | YES |

The matrix CI workflow runs in a degraded mode that skips missing SDKs and reports them as `n/a` rather than failing. With four SDKs in place the matrix has 4×3 = 12 heterogeneous cells (homogeneous runs are covered by each SDK's own CI).
