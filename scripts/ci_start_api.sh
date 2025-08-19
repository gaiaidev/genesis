#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-3002}"
LOG="${API_LOG:-api.log}"

# API'yi başlat
node apps/api/src/index.mjs > "$LOG" 2>&1 &
echo $! > api_pid.txt

# 30 saniyeye kadar bekle; her saniye kontrol
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null; then
    echo "[ci_start_api] Health OK in ${i}s"
    exit 0
  fi
  # süreç yaşıyor mu?
  if ! kill -0 "$(cat api_pid.txt)" 2>/dev/null; then
    echo "[ci_start_api] API crashed while starting. Last logs:"
    tail -n 200 "$LOG" || true
    exit 1
  fi
  sleep 1
done

echo "[ci_start_api] Timed out waiting for health. Last logs:"
tail -n 200 "$LOG" || true
exit 1
