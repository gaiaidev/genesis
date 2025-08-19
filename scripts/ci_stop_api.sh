#!/usr/bin/env bash
set -euo pipefail
if [[ -f api_pid.txt ]]; then
  kill "$(cat api_pid.txt)" 2>/dev/null || true
fi
