# Performance budgets

Conformance criteria — every Lumencast runtime MUST respect these on the target platform's reference hardware.

> Status: draft, refined as runtimes accumulate evidence.

## Reference hardware

| Tier | Description | Examples |
|---|---|---|
| **Browser-modern** | Chromium 120+, Firefox 120+, Safari 17+ on a 2020+ x86_64 / ARM64 laptop | MacBook Air M1, Dell XPS 13 9300 |
| **Browser-low** | Chromium-based, 4-core ARM, 4 GiB RAM | Raspberry Pi 4 in kiosk mode |
| **Native-low** | Flutter / Tauri on the same hardware as Browser-low | Same |

Runtimes target Browser-modern by default. Native targets specify their own tier in their README.

## Budgets

| Metric | Browser-modern | Browser-low | Source |
|---|---|---|---|
| Delta → DOM update p95 | ≤ 50 ms | ≤ 100 ms | LSDP/1 conformance suite, perf scenario `delta-latency` |
| Delta → DOM update p99 | ≤ 100 ms | ≤ 200 ms | Same |
| `mount()` → first paint (snapshot pre-fetched) | ≤ 100 ms | ≤ 250 ms | Performance API `paint-timing` |
| Bundle gz, mode `broadcast` | ≤ 200 KiB | same | Build-time check |
| Bundle gz, mode `control` | ≤ 280 KiB | same | Build-time check |
| Bundle gz, mode `test` | ≤ 350 KiB | same | Build-time check |
| Animation hot-path layout events | 0 | 0 | CDP `Performance.getMetrics` during e2e |
| Reconnect to first valid frame (stable network) | ≤ 1 s | ≤ 2 s | LSDP/1 conformance suite, perf scenario `reconnect` |
| Memory growth on 1 hour stable connection | ≤ 50 MB | ≤ 30 MB | Heap snapshot diff |

## Conformance enforcement

The performance scenarios live in [conformance/v1/scenarios/perf-*.yaml](../conformance/README.md). They are tagged `recommended` rather than `required` — a runtime that misses a budget by 10-20% is degraded but not non-conformant. A runtime that misses by 2× MUST surface the regression in its own CI.

## Why these budgets

- **Delta → DOM ≤ 50 ms** : human perception of "instantaneous" caps at ~100 ms ; a leaf-grain push that takes longer indicates a runtime problem (full DOM diff, missing signal-grain reactivity).
- **Bundle ≤ 200 KiB gz for broadcast** : Pulsar CEF and equivalent low-resource hosts boot from cold cache regularly ; any larger and the time-to-first-render becomes visible to the viewer.
- **0 layout events during animation** : property animation that triggers reflow is the single most common "broadcast graphics looks janky" cause. The runtime contract guarantees this is impossible to author wrong.
- **Reconnect ≤ 1 s** : a stream cannot afford visible state loss when a transient network blip happens.

## Adding new budgets

Same RFC process as protocol changes : open an issue with the metric, the rationale, and the measurement methodology. Budgets become normative only after at least one runtime ships meeting them.
