#!/usr/bin/env bash
# Render runtime configs from .env + the root-only key files, then you deploy with:
#   docker compose --env-file runtime/.env up -d
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "ERROR: copy .env.example to .env and fill it first." >&2; exit 1; }
command -v envsubst >/dev/null || { echo "ERROR: envsubst missing (apt-get install -y gettext-base)." >&2; exit 1; }

set -a; . ./.env; set +a

# Private keys are read from root-only files — never stored in .env or git.
SECRETS_DIR=${SECRETS_DIR:-/root/gw-secrets}
SIGNER_KEY=$(grep -i 'Private key' "$SECRETS_DIR/signer.txt" | grep -oiE '0x[0-9a-f]{64}')
SENDER_KEY=$(grep -i 'Private key' "$SECRETS_DIR/sender.txt" | grep -oiE '0x[0-9a-f]{64}')
[ -n "$SIGNER_KEY" ] && [ -n "$SENDER_KEY" ] || { echo "ERROR: could not read keys from $SECRETS_DIR." >&2; exit 1; }
export SIGNER_KEY SENDER_KEY

# Sanity: refuse to render with empty critical fields.
: "${NETWORK_SUBGRAPH_URL:?set NETWORK_SUBGRAPH_URL in .env}"
: "${GATEWAY_API_KEY:?set GATEWAY_API_KEY in .env}"

mkdir -p runtime
envsubst < templates/gateway.json.tmpl        > runtime/gateway.json
envsubst < templates/escrow-manager.json.tmpl > runtime/escrow-manager.json

# Compose env-file: all .env vars plus the injected keys (gitignored, root-only).
{ grep -vE '^\s*#|^\s*$' .env; echo "SIGNER_KEY=$SIGNER_KEY"; echo "SENDER_KEY=$SENDER_KEY"; } > runtime/.env

chmod 600 runtime/.env runtime/gateway.json runtime/escrow-manager.json
echo "Rendered runtime/{gateway.json,escrow-manager.json,.env}"
echo "Deploy with:  docker compose --env-file runtime/.env up -d"
