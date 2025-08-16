#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${GENESIS_OUTDIR:-build/genesis_out}"
mkdir -p "$OUTDIR"
node scripts/compose_sandbox.mjs
echo "[compose_safe] outputs under: $OUTDIR"
