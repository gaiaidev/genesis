#!/bin/bash
# verify_last_op.sh (read-only)
set -euo pipefail
echo "== GENESIS • SON İŞLEM DOĞRULAMA =="

# 1) Lokal repo göstergeleri
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
HEAD_MSG="$(git log -1 --pretty=%s 2>/dev/null || echo '-')"
echo "Branch: $BR"
echo "Son commit: $HEAD_MSG"

# 2) Dosya varlık kontrolü (Patch #2 için beklenenler)
OK_FILES=0
for f in tests/e2e/health.e2e.test.ts tests/api/health.spec.ts vitest.config.mjs; do
  if [ -f "$f" ]; then echo "✅ var: $f"; OK_FILES=$((OK_FILES+1)); else echo "❌ yok: $f"; fi
done

# 3) Vitest coverage eşiği (min 15 lines) var mı?
if [ -f vitest.config.mjs ] && rg -n --pcre2 'coverage.*lines\s*:\s*1?5' vitest.config.mjs >/dev/null 2>&1; then
  echo "✅ coverage eşiği (lines ≥15) ayarlı"
else
  echo "❌ coverage eşiği bulunamadı (vitest.config.mjs içinde lines:15 beklenirdi)"
fi

# 4) Hızlı test & coverage özeti (read-only)
echo "== Test & Coverage =="
npm run -s test:cov || true
rg -n --pcre2 'All files|Lines\s*:|health' coverage/*/index.html 2>/dev/null || true
# (HTML yoksa vitest stdout özetini göster)
echo "----- vitest stdout son 40 satır -----"
tail -n 40 ./logs/audit_*/test_coverage.txt 2>/dev/null || true

# 5) CI yerel (tam set)
echo "== CI (lokal) =="
npm run -s ci:all || true

# 6) GitHub PR/CI durumu (gh varsa)
if command -v gh >/dev/null 2>&1; then
  echo "== GitHub PR durumu =="
  gh pr status || true
  echo "== CI son işler =="
  gh run list --workflow CI --limit 5 || true
else
  echo "ℹ️ gh CLI yok: PR ve Actions durumunu GitHub UI'dan kontrol edin."
fi

echo "== BİTTİ =="