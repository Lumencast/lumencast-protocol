# LSMLZ-1 — Lumencast scene archive format

> **Status** : 1.0 — initial publication.
> **Identifier** : `LSMLZ/1`
> **Companion to** : [LSML-1](LSML-1.md). LSMLZ packages an LSML scene bundle plus its referenced assets into a single ZIP archive. It is a transport / storage convenience, not a new scene format.
> **Audience** : authoring tools, enrichment editors, broadcast servers, CDNs — any party that exchanges a Lumencast scene as a single artefact.
> **License** : Apache 2.0 (mirrors LSML).

## Table of contents

1. [Premise](#1-premise)
2. [Container format](#2-container-format)
3. [Layout](#3-layout)
4. [Identity & content addressing](#4-identity--content-addressing)
5. [Conformance](#5-conformance)
6. [Versioning](#6-versioning)
7. [Examples](#7-examples)

---

## 1. Premise

LSML (§18) defines the on-disk JSON form of a scene bundle and its associated content-addressed assets, but leaves the **packaging** of bundle + assets unspecified. Producers and consumers are expected to ship a `<scene>.lsml` JSON file alongside a sibling `assets/` directory, and to coordinate transport (e.g. zip-on-upload, manual filesystem copy).

This works for server-side pipelines but is awkward for authoring workflows (one drag-and-drop, one download, one email attachment) and for content-addressing audits (a single archive hash covers every asset). LSMLZ formalises the natural ZIP packaging so all toolchains converge on the same container.

LSMLZ does NOT alter, augment, or replace LSML. The LSML JSON inside an LSMLZ archive is identical to the loose `<scene>.lsml` form, byte for byte. Removing the archive layer (`unzip`) reproduces the exact `.lsml` + `assets/` tree that LSML §18 already specifies.

A reader that does not understand LSMLZ but understands LSML can `unzip` the archive and consume the result with no further changes.

## 2. Container format

### 2.1 Format

LSMLZ archives MUST use the **ZIP file format** as defined by [PKWARE APPNOTE.TXT](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) (section 4 — `.ZIP File Format Specification`). Any compliant ZIP tool MUST be able to read and write LSMLZ archives.

Producers MUST use one of :

- **`STORE` (no compression, method 0)** — for archives where space is not a concern.
- **`DEFLATE` (method 8)** — strongly RECOMMENDED. JSON bundles compress 5–15× ; PNG / JPEG asset entries pay only DEFLATE's container overhead (a few bytes).

Other compression methods (BZIP2, LZMA, ZSTD, etc.) are RESERVED for future LSMLZ versions. A 1.0 reader MAY refuse archives using non-`STORE` / non-`DEFLATE` methods with `LSMLZ_UNSUPPORTED_METHOD`.

ZIP64 extensions are permitted ; archives over 4 GiB or with more than 65,535 entries MUST use ZIP64. In practice a Lumencast scene rarely exceeds tens of MB and ZIP64 is uncommon.

Archives MUST NOT use ZIP encryption. Bundle / asset confidentiality is the responsibility of the transport layer (HTTPS, encrypted storage), not the container.

### 2.2 File extension

The canonical extension is `.lsmlz`.

| Extension | Status | Use |
|---|---|---|
| `.lsmlz` | preferred | Primary extension for scene archives. |
| `.zip` | accepted | Tolerated for transport across systems that filter non-standard extensions ; producers SHOULD prefer `.lsmlz`. |

The double consonant `lz` mnemonically stands for "LSML zipped". It is short, unique, and natural for editors / pickers that already register `.lsml`.

### 2.3 Media type

The IANA-style media type for an LSMLZ archive is :

```
application/lsml+zip
```

The `+zip` suffix per [RFC 6839](https://www.rfc-editor.org/rfc/rfc6839) declares ZIP as the structural syntax. HTTP servers serving archives SHOULD set `Content-Type: application/lsml+zip`.

For HTTP `Accept` negotiation, clients MAY accept `application/zip` to remain interoperable with generic-tool consumers. The LSML JSON inside the archive carries `application/lsml+json` per [LSML §18.2](LSML-1.md#182-media-type).

### 2.4 Magic bytes

The first four bytes of an LSMLZ archive are the standard ZIP local-file-header signature :

```
50 4B 03 04
```

This is identical to any other ZIP file — LSMLZ does not introduce a custom magic-byte sequence. Format detection MUST combine the ZIP signature with one of :

- file extension (`.lsmlz`) — hint, not normative,
- media type — when supplied by the transport,
- the presence of exactly one `*.lsml` entry at the archive root (§3.1) — definitive.

This means an LSMLZ archive renamed to `.zip` and inspected with a generic ZIP tool will still parse cleanly ; the "is this LSMLZ ?" check is structural, not magical.

## 3. Layout

### 3.1 The bundle entry

An LSMLZ archive MUST contain **exactly one** entry whose path matches `*.lsml` (or `*.lsml.json`) **at the archive root** (no path separator before the extension). This is the canonical LSML scene bundle.

The recommended filename is `<scene_id>.lsml` where `scene_id` matches the bundle's `scene_id` field. Readers MUST NOT rely on the filename to derive `scene_id` — the value of record is inside the JSON. The convention exists for human-friendly inspection.

The bundle entry's bytes MUST be the canonical form per LSML §3.1 (JCS RFC 8785) with the `scene_version` placeholder protocol applied per LSML §3.2.

### 3.2 Asset entries

Asset entries live under the `assets/` prefix at the archive root. Each entry's path matches the bundle's `bind.src` references **byte-for-byte** so that unzipping the archive into any directory reproduces an LSML §11-conformant `<scene>.lsml` + `assets/` tree.

Recommended naming : `assets/<sha256>.<ext>` — content-addressed by the asset's sha256 hex (lowercase) with the original file extension. This is the convention every LSML producer SHOULD already use per §11.

LSMLZ does not require content-addressing — any asset path is permitted as long as it matches the bundle's bind references. But LSML §11 recommends content-addressing, and LSMLZ inherits that recommendation.

Multiple bundles MAY reference the same asset (deduplication is implicit when the asset is content-addressed — same hash, same entry). Producers MUST emit each asset entry exactly once.

### 3.3 Reserved authoring prefixes

The following top-level prefixes are RESERVED for authoring-tool diagnostics and are NOT part of the normative scene :

| Prefix | Purpose |
|---|---|
| `_debug/` | Optional artefacts emitted by an authoring tool to ease re-import, post-mortem, or diff workflows (e.g. raw source-file snapshots, mapping traces). Readers MUST ignore the entire `_debug/` subtree when consuming the archive for rendering or distribution. |

Future LSMLZ revisions MAY reserve additional prefixes ; readers MUST treat any entry with a leading underscore in its top-level segment as authoring-tool data and ignore it for runtime consumption.

Authoring tools that want to ship vendor-specific data SHOULD nest it under `_debug/<vendor>/` rather than introducing a new top-level prefix.

### 3.4 Forbidden entries

LSMLZ producers MUST NOT include :

- **Nested archives** (a `.lsmlz`, `.zip`, `.tar.gz`, `.7z`, etc. inside the archive). Readers MUST reject such archives with `LSMLZ_NESTED_ARCHIVE`.
- **Symbolic links** (ZIP can carry symlinks via Unix extra fields). Readers MUST reject any entry with the link bit set. Symlinks open path-traversal and confused-deputy attacks.
- **Absolute paths or `..` segments** in any entry name. Readers MUST reject such archives with `LSMLZ_PATH_TRAVERSAL`.
- **Empty paths or paths containing NUL bytes**. Readers MUST reject with `LSMLZ_INVALID_PATH`.
- **Extra entries outside `<scene>.lsml`, `assets/*`, or `_debug/*`**. Readers MAY reject with `LSMLZ_UNEXPECTED_ENTRY`, but SHOULD ignore them by default for forward-compatibility — a future LSMLZ revision may introduce additional top-level prefixes.

These constraints exist to make LSMLZ unzip safely on any platform without privilege checks beyond what the OS already enforces for the destination directory.

## 4. Identity & content addressing

LSMLZ does not introduce a new content-hash. The archive's identity is derived from its constituents :

- **Bundle identity** = the bundle's `scene_version` per LSML §3 (sha256 of the canonical JSON with the placeholder protocol applied).
- **Asset identity** = the asset's content hash per LSML §11 (typically sha256 of the bytes, expressed in the entry's filename for content-addressed assets).

Two archives are **equivalent** when they contain the same bundle (matching `scene_version`) and the same set of asset hashes. The archive bytes themselves are NOT content-addressed — ZIP allows multiple byte-equivalent encodings for the same logical content (entry order, compression level, timestamps, extra fields).

If a deterministic archive hash is needed for cache keys or audit trails, producers SHOULD compute it over the canonical contents (the bundle's `scene_version` plus a sorted list of asset hashes) rather than over the archive bytes.

## 5. Conformance

### 5.1 Writer requirements

A conforming LSMLZ writer MUST :

1. Produce a ZIP archive per §2.1.
2. Include exactly one `<scene_id>.lsml` (or `<filename>.lsml`) entry at the root, containing the canonical-form bundle bytes per LSML §3.
3. Include each asset referenced by the bundle's `bind.src` at the path expected by the bundle (typically `assets/<hash>.<ext>`).
4. NOT include forbidden entries per §3.4.

A conforming writer SHOULD :

1. Use DEFLATE compression (method 8) at level 6 or higher for the `.lsml` entry. PNG / JPEG asset entries SHOULD be DEFLATEd as well — the storage savings are negligible but the cost is also negligible.
2. Emit the `<scene_id>.lsml` entry FIRST so streaming readers can consume the bundle without reading the entire archive ; assets and other entries follow in lexicographic order for reproducible builds.
3. Set entry timestamps to a fixed sentinel (e.g. 1980-01-01 00:00:00, the ZIP epoch floor) for reproducible builds.

### 5.2 Reader requirements

A conforming LSMLZ reader MUST :

1. Accept any ZIP archive produced per §2 (container format).
2. Locate the bundle entry per §3.1 (the single `*.lsml` / `*.lsml.json` entry at the archive root).
3. Extract asset entries under `assets/` and make them resolvable via the bundle's `bind.src` references.
4. Reject archives that violate §3.4 with the corresponding `LSMLZ_*` error code.
5. Ignore entries under reserved authoring prefixes per §3.3.

A conforming reader SHOULD :

1. Validate the bundle JSON against the LSML schema before exposing primitives to downstream consumers.
2. Verify `scene_version` per LSML §3.2 (recompute the canonical hash and check it matches what the bundle claims).
3. Cap the maximum decompressed size at a configurable budget to mitigate ZIP-bomb attacks. A reasonable default is 100 MiB total decompressed, with a per-entry compression-ratio cap of 100×.

### 5.3 Round-trip stability

Two LSMLZ writers given the same logical input (a bundle and its assets) SHOULD produce **byte-equivalent** archives when configured for reproducible builds (§5.1 SHOULD items). This enables :

- Deterministic build-system caching keyed on the archive bytes.
- Diff-friendly authoring workflows (a `git diff` on two versions of the archive surfaces only the bundle / asset changes, not ZIP metadata noise).

The archive bytes are NOT normative for content-equivalence (§4) — but reproducibility SHOULD be a design target for any production toolchain.

### 5.4 Error codes

Archive-parsing failures surface through the consumer's existing error-reporting channel (e.g. an authoring tool's UI, an LSDP server's structured logs) using the following codes :

| Code | Meaning |
|---|---|
| `LSMLZ_UNSUPPORTED_METHOD` | Archive uses a ZIP compression method other than `STORE` or `DEFLATE` (§2.1). |
| `LSMLZ_NESTED_ARCHIVE` | Archive contains a nested archive entry (§3.4). |
| `LSMLZ_SYMLINK_FORBIDDEN` | Archive contains a symbolic link entry (§3.4). |
| `LSMLZ_PATH_TRAVERSAL` | Archive entry uses an absolute path or a `..` segment (§3.4). |
| `LSMLZ_INVALID_PATH` | Archive entry has an empty path or a path containing NUL bytes (§3.4). |
| `LSMLZ_UNEXPECTED_ENTRY` | Archive contains an entry outside `<scene>.lsml`, `assets/*`, or a reserved authoring prefix (§3.4 — readers MAY emit, SHOULD ignore by default). |
| `LSMLZ_BUNDLE_MISSING` | Archive does not contain exactly one `*.lsml` entry at the root (§3.1). |
| `LSMLZ_DECOMPRESSION_BUDGET` | Archive exceeds the consumer's decompressed-size or compression-ratio budget (§5.2 SHOULD). |

These codes are LSMLZ-specific and live alongside LSML / LSDP error codes. They are NOT emitted on the LSDP wire — archives are parsed before any wire interaction and failures surface to the consumer (authoring tool, build pipeline, broadcast server admin) through whatever channel that consumer uses.

## 6. Versioning

LSMLZ uses semver-aligned identifiers per the [LSML versioning model](LSML-1.md#2-versioning) :

- **Major** (`1`, `2`, …) — backward-incompatible changes to the container layout, magic bytes, reserved prefixes, or conformance.
- **Minor** (`1.0`, `1.1`, …) — additive changes (new reserved prefix, new compression method, new optional metadata).

The archive itself does NOT declare an LSMLZ version inside its bytes. The version of record is **the LSML version of the bundle entry** (the `lsml` field in the `.lsml` JSON). LSMLZ version 1.0 is paired with LSML 1.x ; LSMLZ version 2 will pair with LSML 2.

A reader that doesn't recognise a future LSMLZ feature (e.g. a new top-level prefix) MUST ignore unknown entries (§3.3) and process the bundle + assets it does understand. This is the same forward-compatibility posture LSML §17 takes for unknown primitives and adapters.

## 7. Examples

### 7.1 Minimal archive

A scene with one image asset, packaged with reproducible-build defaults :

```
hello-world.lsmlz                                         (5 KB, DEFLATE)
├── hello-world.lsml                                       (1 KB JSON)
└── assets/
    └── e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.png
                                                          (4 KB binary)
```

The bundle :

```json
{
  "$schema": "https://lumencast.dev/schema/lsml/1.1/schema.json",
  "lsml": "1.1",
  "scene_id": "hello-world",
  "scene_version": "sha256:...",
  "assets": { "allowedHosts": [] },
  "layout": {
    "kind": "image",
    "bind": { "src": "assets/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.png" },
    "alt": "Hello"
  }
}
```

### 7.2 Authoring archive with diagnostics

An archive emitted by an authoring tool that wants to ship round-trip diagnostics alongside the scene :

```
my-scene.lsmlz
├── my-scene.lsml
├── assets/
│   ├── 6b1...d2a.png
│   └── 8f4...91c.jpg
└── _debug/
    ├── source-snapshot.json     (authoring-tool-specific)
    └── mapping-trace.json       (authoring-tool-specific)
```

A runtime / broadcast server consuming this archive ignores `_debug/` entirely and produces the same render as if the `_debug/` subtree were absent. An authoring tool re-importing the archive MAY consume `_debug/` for diff-friendly workflows.

### 7.3 Pure-stdlib reader (Python)

```python
import json, zipfile

def read_lsmlz(path):
    with zipfile.ZipFile(path) as z:
        # §3.1 — locate the single .lsml entry at the root
        names = [n for n in z.namelist()
                 if n.endswith((".lsml", ".lsml.json")) and "/" not in n]
        if len(names) != 1:
            raise ValueError("LSMLZ archive must contain exactly one *.lsml at the root")
        bundle = json.loads(z.read(names[0]))
        # §3.2 — collect asset bytes under `assets/`
        assets = {n: z.read(n) for n in z.namelist() if n.startswith("assets/")}
        # §3.3 — ignore `_debug/` and any other underscore-prefixed top-level
        return bundle, assets
```

No LSMLZ-specific dependency required — Python's `zipfile` + `json` from the standard library suffice.

---

## Reference

- [LSML-1](LSML-1.md) — the scene bundle format LSMLZ packages
- [LSDP-1](LSDP-1.md) — the wire protocol that delivers scene_version updates to clients
- [LSML on-disk format](LSML-1.md#18-on-disk-format) — the loose `.lsml` + `assets/` form that LSMLZ wraps
- [LSDP/LSML error codes](ERROR-CODES.md) — sibling taxonomy ; LSMLZ codes are listed in §5.4 above
