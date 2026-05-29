# Phase 1 — Running lodestar-gateway in local-network

End-to-end harness: a full Graph network in Docker Compose (chain, IPFS, Postgres,
Redpanda, graph-node, indexer-service, tap-agent, tap-aggregator, escrow-manager,
gateway) so we can validate the **query → TAP v2 receipt → RAV → redeem** loop locally
before spending real GRT.

Upstream: [`edgeandnode/local-network`](https://github.com/edgeandnode/local-network)
(Docker Compose v2.24+). Chain id `1337`, automine.

## 1. Vanilla stack (sanity check)

Confirm the harness works on your machine using upstream's pinned gateway first:

```sh
git clone https://github.com/edgeandnode/local-network.git
cd local-network
docker compose up -d            # builds Rust services from source; first run is slow
docker compose ps               # wait for gateway (and deps) to be healthy
```

Test query through the gateway (API key + ports from `.env`):

```sh
curl "http://localhost:7700/api/subgraphs/id/BFr2mx7FgkJ36Y6pE5BiXs1KmNUmVDCnL82KUSdcLW1g" \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeef" \
  -d '{"query": "{ _meta { block { number } } }"}'
```

Watch the receipt/result stream on Redpanda:

```sh
docker exec -it redpanda rpk topic consume gateway_client_query_results --brokers="localhost:9092"
```

If subgraphs report `too far behind` during startup, advance blocks:
`scripts/mine-block.sh 10`.

## 2. Swap in our fork

The dev-override pattern mounts a locally-built binary over the image's
`/usr/local/bin/graph-gateway`, reusing local-network's `run.sh` (which generates
`config.json`) unchanged. The binary must be a **Linux ELF for the container's arch**.

On macOS (Docker Desktop runs linux/arm64 natively), build it inside Docker — no
cross-compile toolchain required:

```sh
# in the gateway repo
./scripts/build-linux-gateway.sh        # -> target/linux/lodestar-gateway
```

Add the override and the binary path to local-network's `.env.local` (gitignored):

```sh
# local-network/.env.local
GATEWAY_BINARY=/abs/path/to/gateway/target/linux/lodestar-gateway
COMPOSE_FILE=docker-compose.yaml:compose/dev/gateway.yaml
```

`compose/dev/gateway.yaml` is provided in this fork's tree (copy it into your
local-network checkout's `compose/dev/`). Then restart just the gateway:

```sh
docker compose up -d gateway
docker compose logs -f gateway          # confirm our binary boots + serves
```

Re-run the test query from step 1 — it should now be served by `lodestar-gateway`.

## Config notes (verified against our v27.6.0)

local-network's `run.sh` generates a config that deserialises cleanly against our
binary. Reference minimal shape for a solo deploy:

- `api_keys`: `Fixed` array of `{ key, user_address, query_status: "ACTIVE" }` — no Studio.
- `payment_required: false` for testing (skip consumer billing).
- `exchange_rate_provider: 1.0` (Fixed GRT/USD) — no RPC needed.
- `receipts: { chain_id, payer, signer, verifier }` — TAP v2 sender; `verifier` is the
  GraphTallyCollector address.
- `attestations: { chain_id, dispute_manager }` — **required**.
- `subgraph_service` — SubgraphService address.
- `kafka.bootstrap.servers` — points at Redpanda; data-science exporters use it.

`run.sh`'s config includes an `indexer_selection_retry_limit` field that our v27.6.0
no longer defines — harmless, `Config` ignores unknown fields.

## Verifying the payment loop

The point of Phase 1 is the money path, not just the query:

1. Query through the gateway → indexer-service validates the v2 receipt.
2. tap-agent aggregates receipts into a RAV (watch its logs).
3. escrow-manager keeps the sender's PaymentsEscrow topped up.
4. indexer-agent redeems the RAV on-chain after allocation close.

Inspect the network subgraph (allocations, provisions) at
`http://localhost:8000/subgraphs/name/graph-network` — see CHEATSHEET.md for a query.
