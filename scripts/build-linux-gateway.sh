#!/usr/bin/env bash
# Build a DEBUG Linux binary of lodestar-gateway and drop it at
# target/linux/lodestar-gateway, for mounting into the local-network stack.
#
# Uses Docker buildx so it works on macOS (builds inside a linux/<host-arch>
# container — no cross-compile toolchain needed). Then point the dev override:
#   GATEWAY_BINARY=$(pwd)/target/linux/lodestar-gateway
#   COMPOSE_FILE=docker-compose.yaml:compose/dev/gateway.yaml
set -euo pipefail
cd "$(dirname "$0")/.."

out="target/linux"
mkdir -p "$out"

# --output type=local extracts the `export` stage's filesystem (just the binary).
docker buildx build \
  --file Dockerfile.dev \
  --target export \
  --output "type=local,dest=${out}" \
  .

chmod +x "${out}/lodestar-gateway"
echo "Built: ${out}/lodestar-gateway"
file "${out}/lodestar-gateway" 2>/dev/null || true
