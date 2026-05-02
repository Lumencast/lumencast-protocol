# Lumencast

> **The missing standard for server-driven displays.**
> A wire protocol, a typed schema, and a multi-runtime client kit — Apache 2.0, multi-language, broadcast-grade and IoT-grade.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Spec: LSDP/1](https://img.shields.io/badge/Protocol-LSDP%2F1-orange.svg)](spec/LSDP-1.md)
[![Format: LSML 1.0](https://img.shields.io/badge/Format-LSML%201.0-purple.svg)](spec/LSML-1.md)

---

## What Lumencast is

A serveur authoritatif détient un état temps-réel. Il doit le **pousser** à un display passif (browser, kiosque natif, OBS browser source, iframe, terminal, mobile) qui le rend visuellement. Le display n'a aucune logique métier, ne mute pas le state local, ne fait aucun calcul. Il rend, point.

Lumencast est le **kernel commun** de ce pattern :

- **LSDP/1** — *Leaf State Delta Protocol* — un protocole WebSocket qui pousse de l'état au niveau de la feuille (`path → value`), avec snapshot+delta sequenced, gap detection, reconnect schedule, et token rotation.
- **LSML 1.0** — *Lumencast Scene Markup Language* — un format JSON content-addressé décrivant un arbre de primitives fermées (`stack`, `grid`, `frame`, `text`, `image`, `shape`, `media`, `repeat`) avec bindings, animations encadrées, et metadata d'inputs opérateur.
- **Multi-runtime** — implémentations clientes en TypeScript (browser), bientôt Vue, Svelte, Flutter, TUI.
- **Multi-langage server SDK** — TypeScript / Go / Rust / Python en wave 1, Elixir / Kotlin / .NET / Ruby en community.

## Why Lumencast exists

Le pattern "serveur push d'état → display passif" est partout, et **systématiquement réimplémenté ad-hoc**. Broadcast overlays. Trading dashboards. NOC walls. Esports brackets. ATC consoles. Industrial SCADA. Live betting tickers. Conference Q&A boards. Digital signage. Game spectator UIs.

Chaque vertical réinvente :
- Un format WebSocket custom (souvent JSON arbitraire, parfois CBOR ad-hoc)
- Un client-side renderer (souvent React libre, sans schema, avec `dangerouslySetInnerHTML`)
- Un protocole de reconnexion (souvent buggé)
- Un schema (souvent absent)

**Aucun outil OSS existant ne combine** :

| Outil | Manque |
|---|---|
| **Phoenix LiveView** | Verrouillé Elixir/Phoenix. Pousse du HTML, pas de l'état. |
| **Hotwire / Turbo Streams** | Verrouillé Rails. HTML again. |
| **HTMX + SSE** | DOM-only, pas de schema typé, surface XSS large. |
| **Liveblocks** | Bidirectionnel CRDT — overkill pour display passif. SaaS. |
| **PartyKit** | Pubsub pur, pas de contrat de rendu. |
| **Apollo / urql subs** | GraphQL push subscriptions — typed mais pas de protocole de rendu. |
| **Caspar CG** | C++ industrie 2007, courbe rude, désuet pour le web stack. |
| **Singular.live / Vizrt / Streamlabs** | Closed-source, vendor lock, payant. |

Lumencast comble le trou.

## The 3 invariants

Trois propriétés conjointes — aucun outil concurrent ne les combine :

### 1. Push leaf-grain

L'état traverse en patches `path → value` au niveau de la feuille (`players.1.score = 42`, jamais `players = [whole array]`). Le client maintient un store `path → signal`. **Seuls les composants qui lisent ce path re-rendent**. Pas de diff DOM, pas de réconciliation custom.

Un serveur peut pousser **45 deltas/sec sur 100 paths** sans saturer le client. La latence est bornée par le degré du graphe de dépendances, pas par la taille du state.

### 2. Catalogue de primitives fermé

Le client ne rend **que** des primitives d'un catalogue clos. Pas d'extension custom user-side. Pas d'`eval`. Pas de `dangerouslySetInnerHTML`. Pas d'arbitrary HTML.

- **Sécurité par construction** — surface XSS impossible.
- **Bundle size garanti** — aucune scène ne peut faire grossir le runtime.
- **API stability garantie** — la forme d'une scène d'aujourd'hui est lisible dans 10 ans.

Étendre Lumencast avec un nouveau type de rendu (chart, WebGL surface, 3D scene) = **release majeure du runtime**, pas une décision quotidienne.

### 3. Bundle de scène content-addressé

Le bundle LSML est immuable, identifié par son hash sha256. URL de fetch : `?v={hash}`. Cache forever. Plusieurs versions co-existent.

- **Rollback instantané** — switcher de version = switcher d'URL.
- **Aucune cohérence à gérer** — deux clients qui chargent au même instant peuvent voir deux versions différentes, mais chacun a une version cohérente.
- **CDN-friendly** — content-hash + cache forever = stratégie HTTP standard.

## Status

| | |
|---|---|
| **Repo** | This is the protocol + format spec. SDKs and runtimes live in sibling repos. |
| **Spec freeze** | LSDP/1 and LSML 1.0 are **draft** — not frozen yet. Breaking changes possible until v1.0 of this repo. |
| **Reference SDKs** | `lumencast-js` (TypeScript runtime + Node server), `lumencast-go` (Go server + CLI). Rust + Python in P2. |
| **Conformance suite** | Golden fixtures + scenarios in `conformance/`. Reusable cross-language. |

## Quick links

- [LSDP/1 — wire protocol spec](spec/LSDP-1.md)
- [LSML 1.0 — scene format spec](spec/LSML-1.md)
- [Error code taxonomy](spec/ERROR-CODES.md)
- [Conformance suite](conformance/README.md)
- [Governance](GOVERNANCE.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Implementations

| Repo | Language | Layer | Status |
|---|---|---|---|
| `lumencast-protocol` (this) | spec + fixtures | 1+2 | draft |
| `lumencast-js` | TypeScript | 1+2+3+4 | P0 |
| `lumencast-go` | Go | 1+4 + CLI | P0 |
| `lumencast-rs` | Rust | 1+4 | P2 |
| `lumencast-py` | Python | 1+4 | P2 |
| `lumencast-flutter` | Dart/Flutter | 3 (native) | P3 |

(Layer numbers refer to the [architecture document](GOVERNANCE.md#architecture).)

## License

Apache License 2.0 — see [LICENSE](LICENSE).

## Etymology

"Lumencast" : *lumen* (light, scene, the rendered output) + *cast* (broadcasting, multicast, podcast — the act of pushing). The wire that carries the cast is **LSDP**. The format that describes the scene is **LSML**.
