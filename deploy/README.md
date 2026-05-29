# Deploying lodestar-gateway (Arbitrum One mainnet)

A real, fund-handling gateway: our gateway + a public tap-aggregator + the graph-tally
escrow-manager + a Redpanda bus. Host: `89.167.109.4`.

## Prerequisites (on the VPS)

- Docker + compose, `gettext-base` (for `envsubst`).
- `lodestar-gateway:latest` image built (`docker build -t lodestar-gateway:latest /opt/gateway`).
- Sender + signer keypairs in `/root/gw-secrets/{sender,signer}.txt` (mode 600).
- **Sender funded** on Arbitrum One: a little ETH for gas + the GRT you want to back escrow with.

## Configure

```sh
cp .env.example .env
# Fill: NETWORK_SUBGRAPH_URL (+ NETWORK_SUBGRAPH_AUTH), GATEWAY_API_KEY.
# Verified contract addresses + sender address are pre-filled.
```

## Render + deploy

```sh
./render.sh                                  # -> runtime/{gateway.json,escrow-manager.json,.env}
docker compose --env-file runtime/.env up -d
docker compose --env-file runtime/.env ps
docker compose --env-file runtime/.env logs -f escrow-manager   # watch authorizeSigner + escrow deposit
```

## What happens on first boot

1. `escrow-manager` (`authorize_signers: true`) sends `authorizeSigner` from the **sender**,
   binding the **signer** on GraphTallyCollector, then approves/deposits GRT into PaymentsEscrow
   up to `GRT_ALLOWANCE`, driven by query debt read from the `gateway_queries` Kafka topic.
2. `tap-aggregator` exposes `:7610` — **this URL + the sender address are what indexers whitelist**
   (`tap.sender_aggregator_endpoints`).
3. `gateway` serves `:7700`, signs TAP v2 receipts with the signer key.

## Onboarding an indexer

On the indexer, add to its TAP config and restart indexer-service + tap-agent:

```
[tap.sender_aggregator_endpoints]
0xE941D672C00A730AE675945007A6C0C76057C51b = "http://89.167.109.4:7610"
```

(Use the sender address from `.env`; the aggregator URL is this box's `:7610`, ideally behind TLS.)

## Test query

```sh
curl "http://89.167.109.4:7700/api/subgraphs/id/<SUBGRAPH_ID>" \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer <GATEWAY_API_KEY>" \
  -d '{"query":"{ _meta { block { number } } }"}'
```

## Notes / TODO

- `exchange_rate_provider` is a fixed GRT/USD number (`GRT_USD`) — approximate; refine or switch to
  the RPC/Chainlink provider variant for accurate budgeting.
- `GRAPH_TALLY_COLLECTOR` / `SUBGRAPH_SERVICE` MUST match what the target indexer uses
  (`receipts_verifier_address_v2`, `subgraph_service_address`) or it rejects our receipts.
- Aggregator should sit behind TLS (reverse proxy) before sharing the URL widely.
- Redpanda runs in `dev-container` mode (auto-creates topics); fine for a single-box deploy.
