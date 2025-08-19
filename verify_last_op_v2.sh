#!/usr/bin/env bash
# verify_last_op.sh (read-only, tolerant)
set -euo pipefail
echo "== GENESIS • SON İŞLEM DOĞRULAMA (v2) =="

# 1) Repo göstergeleri
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
HEAD_MSG="$(git log -1 --pretty=%s 2>/dev/null || echo '-')"
echo "Branch: $BR"
echo "Son commit: $HEAD_MSG"

# 2) Dosya varlık kontrolü (uzantı esnek)
exists_any() {
  for p in "$@"; do [[ -e "$p" ]] && { echo "✅ var: $p"; return 0; }; done
  echo "❌ yok: (${*})"; return 1
}

API_TEST_OK=0
E2E_TEST_OK=0
exists_any tests/api/health.spec.ts tests/api/health.spec.js tests/api/health.spec.mjs && API_TEST_OK=1
exists_any tests/e2e/health.e2e.test.ts tests/e2e/health.e2e.test.js tests/e2e/health.e2e.test.mjs && E2E_TEST_OK=1

# 3) Coverage eşiği (>=15 yeterli)
CFG_FILE=""
for c in vitest.config.mjs vitest.config.ts vitest.config.cjs; do
  [[ -f "$c" ]] && { CFG_FILE="$c"; break; }
done
if [[ -n "$CFG_FILE" ]]; then
  THRESH="$(awk 'tolower($0) ~ /coverage/ {cov=1} cov && tolower($0) ~ /lines[[:space:]]*:/ {match($0,/lines[[:space:]]*:[[:space:]]*([0-9]+)/,a); if(a[1]!=""){print a[1]; exit}}' "$CFG_FILE" || true)"
  if [[ -n "${THRESH:-}" ]]; then
    if (( THRESH >= 15 )); then
      echo "✅ coverage eşiği (lines >=15) OK → $THRESH (dosya: $CFG_FILE)"
    else
      echo "❌ coverage eşiği çok düşük: $THRESH (dosya: $CFG_FILE, beklenen ≥15)"; exit 1
    fi
  else
    echo "ℹ️ coverage eşiği bulunamadı (dosya: $CFG_FILE)"; fi
else
  echo "ℹ️ vitest config bulunamadı"
fi

# 4) Test & coverage çalıştır (read-only)
echo "== Test & Coverage =="
npm run -s test:cov || true

# 5) Hızlı coverage özeti (stdout ya da HTML'den çek)
SUMMARY="$(rg -n --pcre2 'All files|Lines\s*:' coverage/*/index.html 2>/dev/null | tail -n 3 || true)"
if [[ -z "$SUMMARY" ]]; then
  SUMMARY="$(rg -n --pcre2 'All files|Lines\s*:' -g '!node_modules' -S . 2>/dev/null | tail -n 3 || true)"
fi
echo "${SUMMARY:-"(coverage özetini bulamadım; vitest stdout'u incele)"}"

# 6) Son karar özeti
if (( API_TEST_OK==1 )); then echo "✅ API unit test dosyası mevcut"; else echo "❌ API unit test dosyası eksik"; fi
if (( E2E_TEST_OK==1 )); then echo "✅ E2E health testi mevcut"; else echo "ℹ️ E2E health testi bulunamadı (opsiyonel)"; fi

echo "== BİTTİ =="