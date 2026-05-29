# lodestar-gateway

An independent [Graph Network](https://thegraph.com) gateway for **Arbitrum One**, post-Horizon.

A gateway sits between data consumers and indexers: it discovers indexers from the network subgraph,
routes each query to the best of them, pays them with [TAP](https://github.com/semiotic-ai/timeline-aggregation-protocol)
v2 receipts, and shields consumers from individual indexers being slow, stale, or unavailable. The
Graph Network is permissionless about who may run one — `lodestar-gateway` is exactly that: a
self-funded, independently operated gateway rather than a reseller.

> **Fork notice.** Forked from [`edgeandnode/gateway`](https://github.com/edgeandnode/gateway)
> (MIT, v27.6.0). Upstream remains the canonical implementation and source of truth for the
> query-serving and TAP logic; we track it and diverge only where an independent operator's needs
> differ (branding, build, deployment). See [`LICENSE`](LICENSE) for the original copyright.

## Status

**Proven working against the live Arbitrum One network.** The binary boots, loads the real network
topology (15,845+ subgraphs, 182 indexers), authenticates queries, selects real indexers, signs TAP
v2 receipts, and dispatches them — confirmed end-to-end against production indexers. The only thing
between this and serving *paid* queries is operational, not code: funding the sender's escrow and
having indexers onboard our sender→aggregator mapping. (Live indexers currently return `402 Payment
Required` precisely because escrow isn't funded yet.)

See [`PLAN.md`](PLAN.md) for the full proof writeup, verified Arbitrum One / Sepolia contract
addresses, and the roadmap to live operation.

## How it works

The core query path (inherited from upstream):

- **Indexer discovery** — periodically queries the **network subgraph** (via a set of *trusted
  indexers*) for subgraphs, deployments, and active allocations, then asks each indexer's
  `indexer-service` for version, indexing status, and Agora cost models.
- **Query routing** — resolves a subgraph ID → latest deployment with an indexer near chain head,
  rewrites it into an "indexer request", and selects up to 3 indexers via a weighted model over
  success rate, latency, seconds-behind-chain, slashable GRT, and fee-vs-budget
  ([candidate-selection](https://github.com/edgeandnode/candidate-selection)). First valid response
  wins; performance feeds back into selection.
- **Payments (TAP v2)** — the gateway is a TAP **sender**: every indexer request carries a signed v2
  receipt. A fee-control system targets an average fee per query, clamped to budget. Receipts are
  aggregated into RAVs by a **tap-aggregator** and settled against escrow by **graph-tally**.
- **Auth** — each client query carries an API key (32 hex chars). For a solo, self-funded gateway the
  consumer side is deliberately minimal: static keys, `payment_required: false`, no Studio billing.
- **Data science** *(optional)* — exports `gateway_queries` / `gateway_attestations` to Kafka and
  consumes `gateway_blocklist`.

## Building

**Linux / Docker** build out of the box (`rdkafka` statically builds vendored `librdkafka`):

```sh
cargo build --release          # or: docker build -t lodestar-gateway:latest .
```

**macOS** — the vendored `librdkafka` C++ wrapper won't compile against modern libc++, so link the
Homebrew copy via the opt-in `dynamic-kafka` feature:

```sh
brew install librdkafka openssl@3 cyrus-sasl krb5 zstd lz4 pkgconf
cargo build --release --features dynamic-kafka
```

A gitignored `.cargo/config.toml` sets the `PKG_CONFIG_PATH` / `OPENSSL_ROOT_DIR` the build needs
(template in [`PLAN.md`](PLAN.md)).

## Running

The gateway takes a single JSON config file as its first argument
(`lodestar_gateway::config::Config` in [`src/config.rs`](src/config.rs)):

```sh
lodestar-gateway path/to/config.json
```

A full production stack — gateway + tap-aggregator + graph-tally escrow-manager + Redpanda, with
config templates and a render script — lives in [`deploy/`](deploy/). See
[`deploy/README.md`](deploy/README.md) to stand it up on Arbitrum One.

Notes:
- The API server only binds **after** the first network-subgraph snapshot loads (~60s on mainnet).
- `trusted_indexers` must point at an `indexer-service`-style endpoint (it expects the
  `{graphQLResponse, attestation}` envelope), not a plain GraphQL/decentralised-gateway URL.

## Operational notes

- **Logs** — `RUST_LOG` (e.g. `RUST_LOG="info,lodestar_gateway=debug"`); per-request spans are labelled
  `client_request`, per-indexer events `indexer_request`.
- **Metrics** — Prometheus at `:${port_metrics}/metrics` ([`src/metrics.rs`](src/metrics.rs)).
- **Errors** — client-facing errors are defined in [`src/errors.rs`](src/errors.rs).

## License

MIT — see [`LICENSE`](LICENSE). Original copyright Edge & Node and contributors; fork maintained by
the Lodestar team.
