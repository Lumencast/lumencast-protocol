# Benchmarks methodology

How Lumencast SDKs and runtimes measure the performance budgets declared in [PERFORMANCE.md](PERFORMANCE.md). This document is **prescriptive** — every implementation that publishes benchmarks does so per these rules, so numbers across SDKs and runtimes are comparable.

> Status: draft. Refined as more SDKs accumulate evidence and edge cases surface.

## Table of contents

1. [What we measure](#1-what-we-measure)
2. [Reference hardware](#2-reference-hardware)
3. [Measurement primitives](#3-measurement-primitives)
4. [Per-budget methodology](#4-per-budget-methodology)
5. [Reporting](#5-reporting)
6. [Conformance binding](#6-conformance-binding)

## 1. What we measure

Six budgets in PERFORMANCE.md, plus a memory budget. Each has a method, a tool, and a tier-aware threshold.

| Budget | Tool category | Output |
|---|---|---|
| Delta → DOM update p50 / p95 / p99 | Browser DevTools / CDP / framework profiler | Latency distribution in ms |
| `mount()` → first paint | Performance API (`performance.mark`) | Single ms value |
| Bundle gz size per mode | Build tool (Vite, esbuild, webpack-bundle-analyzer) | KiB gz |
| Animation hot-path layout events | CDP `Performance.getMetrics.LayoutCount` | Integer count |
| Reconnect time (stable network) | Conformance harness with virtual clock | ms |
| Memory growth on 1h connection | Heap snapshot diff (Chrome DevTools / pprof) | Resident MiB delta |

We **do not measure** :

- Server-side throughput in this document — server SDKs publish their own benchmarks
- Network transit latency (out of scope, varies by deployment)
- Cold-start of the host (Pulsar CEF / OBS Browser Source) — too host-specific

## 2. Reference hardware

Every published benchmark MUST declare which tier it ran on.

| Tier | Description | Sample machines |
|---|---|---|
| **browser-modern** | Chromium 120+ / Firefox 120+ / Safari 17+ on a 2020+ x86_64 or ARM64 laptop | MacBook Air M1 (8 GB), Dell XPS 13 9300, Framework 13 (12th gen i5+) |
| **browser-low** | Chromium-based, 4-core ARM, 4 GiB RAM | Raspberry Pi 4 (4 GB), Pi 5 (4 GB) running Raspberry Pi OS Bookworm + Chromium |
| **native-low** | Same hardware as browser-low, but native runtime (Flutter / Tauri) | Same |
| **server-modest** | 4 vCPU, 8 GiB RAM, Linux — typical small VPS | Hetzner CX31, AWS t3.medium |

Numbers from one tier MUST NOT be reported as if they applied to another. A benchmark must explicitly state its tier.

## 3. Measurement primitives

### 3.1 Latency

Use the host's high-resolution clock :

- Browser : `performance.now()` (microsecond resolution, monotonic)
- Node : `performance.now()` from `node:perf_hooks` (same)
- Go : `time.Now()` — nanosecond resolution
- Rust : `std::time::Instant::now()`

Always measure as a **delta between two timestamps**, never absolute. Report :

- **min** — useful but easy to game with cherry-picked runs
- **p50** — the typical experience
- **p95** — the long-tail-aware threshold most budgets target
- **p99** — used for anomaly detection
- **max** — failure proof

Sample size : at least 1000 events per measurement. Less than that, the percentiles are noise.

### 3.2 Layout events

Browser only. Use the Chrome DevTools Protocol (CDP) :

```javascript
const cdp = await page.target().createCDPSession();
await cdp.send('Performance.enable');
const before = (await cdp.send('Performance.getMetrics')).metrics.find(m => m.name === 'LayoutCount').value;
// ... trigger the animation
const after = (await cdp.send('Performance.getMetrics')).metrics.find(m => m.name === 'LayoutCount').value;
const layouts = after - before;
```

Layout events on the animation hot path MUST be **0**. Any non-zero result is a bug, not a budget breach — animations that trigger reflow are forbidden by LSML 1.0 § 6.

### 3.3 Bundle size

Measure the **gzipped** byte count of the JavaScript chunks the runtime loads in a given mode :

- `broadcast` mode chunks only
- `control` mode chunks (broadcast + control)
- `test` mode chunks (broadcast + control + test)

Use `gzip -9` for measurement. Build configurations should also use gzip — not Brotli — for the budget check, because gzip is the universal floor. (Brotli numbers are also fine to report, but gzip is the budget-binding one.)

### 3.4 Memory growth

Browser : Chrome DevTools heap snapshot before / after a 1-hour idle connection. Diff the **retained size** of leaked objects.

Native : `pprof` heap profiles or platform equivalent.

Acceptable growth : ≤ 50 MiB on browser-modern, ≤ 30 MiB on browser-low. Anything more indicates a leak.

## 4. Per-budget methodology

### 4.1 Delta → DOM update

**What** : the time between a server-emitted `delta` arriving on the wire and the corresponding DOM mutation being committed.

**How** :

1. Start a Lumencast runtime in `broadcast` mode, attached to a controlled mock server
2. Server emits a `delta` frame with `ts: <iso>` set to the current time (per LSDP/1 envelope optional `ts` field)
3. Runtime computes `delta_to_dom_ms = paint_ts - delta_arrived_ts` where :
   - `delta_arrived_ts` = `performance.now()` at the WS `onmessage` handler invocation
   - `paint_ts` = `performance.now()` after the React commit (use `useLayoutEffect` callback or React DevTools profiler)
4. Repeat 1000+ times with varied delta shapes (single-patch, multi-patch, repeat-targeted)
5. Compute p50 / p95 / p99 / max

**Threshold** : p95 ≤ 50 ms on browser-modern, ≤ 100 ms on browser-low.

**Tool** : Playwright + a custom test harness, or a hand-rolled Node script + Puppeteer.

### 4.2 `mount()` → first paint

**What** : the time between `mount()` returning and the first DOM commit that includes the snapshot's bound state.

**How** :

1. Pre-fetch the scene bundle so it's in HTTP cache
2. Open a new page, `performance.mark('mount-start')`, call `mount(...)`, return
3. After the runtime emits `onStatus("live")`, check that the bound text primitives have non-default content
4. `performance.mark('first-paint')` at that point
5. Compute `first_paint_ms = first-paint - mount-start`
6. Repeat 100 times, take p95

**Threshold** : p95 ≤ 100 ms browser-modern, ≤ 250 ms browser-low.

**Tool** : Playwright with Performance API access via `page.evaluate`.

### 4.3 Bundle size

**What** : the gzipped byte count of the JavaScript chunks the runtime loads in each of the three modes.

**How** :

1. Build the runtime in production mode with the canonical Vite library config
2. For each mode (`broadcast` / `control` / `test`), enumerate the chunks the dynamic import resolves to
3. Concatenate (or sum, identical result for gzip on independent files) the gzipped sizes
4. Record `<mode>_gz_bytes`

**Threshold** : per [PERFORMANCE.md](PERFORMANCE.md) — 200 / 280 / 350 KiB gz.

**Tool** : the `check-bundle-size.mjs` script that ships with `lumencast-js` (other-language SDKs adopt the same logic in their build tooling).

### 4.4 Animation layout events

**What** : the integer number of DOM layout events emitted during a Lumencast animation transition.

**How** :

1. Start a runtime with a scene containing an animatable element (a `frame` with `animate.transform.translate` keyframes)
2. Trigger the animation (e.g. emit a delta that changes the bound state)
3. Read the CDP `Performance.LayoutCount` metric before and after the transition window
4. The difference MUST be 0

**Threshold** : 0. No tolerance.

**Tool** : Playwright + CDP session (see § 3.2).

### 4.5 Reconnect time

**What** : the time from a transport failure (ws close) to the runtime emitting `onStatus("live")` again with a fresh snapshot processed.

**How** :

1. Start a runtime, wait for `onStatus("live")`
2. Force-close the underlying WebSocket (test-only API or proxy-level intervention)
3. `performance.mark('disconnect')`
4. When `onStatus("live")` fires again, `performance.mark('reconnected')`
5. Compute the delta

**Threshold** : ≤ 1 s on browser-modern with stable network, ≤ 2 s on browser-low.

**Tool** : conformance harness with a proxy that can drop the connection on demand. The `lumencast` CLI's conformance runner ships this capability via the `seq-gap-triggers-reconnect` and similar scenarios.

### 4.6 Memory growth

**What** : the difference between heap usage at `t=0` (just after `onStatus("live")`) and `t=3600s` (1 hour later) on a connection that's been receiving deltas continuously.

**How** :

1. Start a runtime in `broadcast` mode against a mock server that emits 10 deltas/sec
2. Trigger a manual GC, snapshot heap, record retained size
3. Wait 1 hour while deltas continue
4. Trigger another manual GC, snapshot heap, record retained size
5. Compute `delta_mb = after_mb - before_mb`

**Threshold** : ≤ 50 MiB browser-modern, ≤ 30 MiB browser-low. Higher indicates a memory leak (typically signals not being unsubscribed, or stale render bundles not being released).

**Tool** : Chrome DevTools heap snapshots, automatable via Puppeteer's `page.metrics()` and CDP `HeapProfiler.takeHeapSnapshot`.

## 5. Reporting

Every published benchmark MUST include :

- Lumencast SDK / runtime version
- Spec version implemented (LSDP/1.0, LSML 1.0)
- Hardware tier
- OS + browser version (for browser tiers)
- Network conditions (LAN, Wi-Fi, gigabit, etc.)
- Sample size (number of runs / events per measurement)
- The full distribution (p50, p95, p99, max) — not just the headline number

Each SDK SHOULD ship a `BENCHMARKS.md` in its own repo with current numbers. Cross-link from the canonical implementation list.

Sample skeleton :

```markdown
## delta → DOM update

| Tier | Sample size | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| browser-modern | 10 000 | 8.2 ms | 24.5 ms | 41.7 ms | 67.3 ms |
| browser-low | 5 000 | 21.4 ms | 73.9 ms | 116.4 ms | 198.0 ms |

Hardware : MacBook Air M1 (16 GB) / Raspberry Pi 4 (4 GB)
Browser : Chromium 132 stable
Tested with `lumencast/runtime` v0.1.0 against `lumencast/dev-server` v0.1.0
```

## 6. Conformance binding

Performance budgets are **conformance criteria** for the `extended` tag (per the conformance manifest). A runtime that fails by 10–20% is degraded but conformant ; a runtime that fails by 2× is non-conformant and may not claim Lumencast compliance without qualification.

The performance scenarios live in `conformance/v1/scenarios/perf-*.yaml`. They are tagged `recommended` for v0 (because not every CI environment can produce repeatable timings — a virtualized CI runner is not the right reference hardware). Implementations SHOULD run them on a fixed reference machine at release time, not in PR CI.

## 7. CI integration

For CI (PR-time) checks :

- Bundle size check (deterministic, hardware-independent) — runs every CI build, fails on regression
- Animation layout-events check (deterministic on any browser) — runs in e2e CI
- Memory-growth check — too long for PR CI ; runs as a nightly job

For pre-release benchmarks :

- Run all six measurements on the reference machine declared in the SDK's `BENCHMARKS.md`
- Update the document
- Tag the release only after numbers are within budget

## 8. Reporting regressions

If a Lumencast release ships measurable regressions :

- Document the regression in CHANGELOG.md with measured numbers
- Add a fix to the milestone for the next minor release
- Surface in the release notes if the regression breaches a `required` budget

The point of this discipline isn't to chase microseconds. It's to catch the **real** regressions — a routine refactor that 5×'s a hot path is the kind of thing that happens, and benchmarks are how we notice without manual auditing.
