#!/bin/bash
# genesis_readonly_audit_$(date +%Y%m%d_%H%M%S).sh
set -euo pipefail

TS="$(date +'%Y%m%d_%H%M%S')"
LOG_DIR="logs/audit_$TS"
OUT_DIR="artifacts/reports"
AUDIT_OUT="build/audit_out_$TS"     # Yalnızca ignored path
REPORT="$OUT_DIR/GENESIS_AUDIT_REPORT_$TS.md"

mkdir -p "$LOG_DIR" "$OUT_DIR" "$AUDIT_OUT"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_DIR/steps.log"; }

# --- Güvenlik: Başta çalışma ağacı temiz mi? (tracked değişiklik yok) ---
log "Pre-flight: git cleanliness check"
git status --porcelain=v1 > "$LOG_DIR/git_status_before.txt"
if [ -s "$LOG_DIR/git_status_before.txt" ]; then
  log "WARN: Working tree has changes (tracked). This audit will NOT modify code, but recommend running on a clean tree."
fi

# --- Repo metrikleri ---
log "Repo metadata"
{
  echo "### Repo"
  echo "- HEAD: $(git rev-parse --short HEAD)"
  echo "- Branch: $(git rev-parse --abbrev-ref HEAD)"
  echo "- Last tag: $(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
  echo "- Total commits: $(git rev-list --count HEAD)"
} | tee "$LOG_DIR/repo_meta.txt" >/dev/null

# --- Boyut & dosya sayımı (yaklaşık) ---
log "Counting files (tracked) and biggest files"
git ls-files | wc -l | awk '{print "tracked_files=" $1}' | tee "$LOG_DIR/filecounts.txt" >/dev/null
# En büyük 20 tracked dosya
git ls-files -z | xargs -0 -I{} sh -c 'wc -c "{}" 2>/dev/null || true' | sort -nr | head -20 > "$LOG_DIR/top_big_files.txt" || true

# --- SLOC / cloc (varsa) ---
log "SLOC (cloc varsa)"
if command -v cloc >/dev/null 2>&1; then
  cloc --vcs=git --json > "$LOG_DIR/cloc.json" || true
else
  # Basit yedek: sadece js/ts mjs cjs say
  find apps scripts -type f \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print0 \
    | xargs -0 wc -l > "$LOG_DIR/sloc_fallback.txt" || true
fi

# --- Lint (rapor, fail etme) ---
log "ESLint (rapor amaçlı)"
npx -y eslint . || true | tee "$LOG_DIR/eslint.txt" >/dev/null

# --- TypeScript (noEmit) ---
log "TypeScript typecheck"
npx -y tsc --noEmit | tee "$LOG_DIR/tsc.txt" || true

# --- Test & Coverage (rapor) ---
log "Vitest (coverage ile, rapor topla)"
( npm run -s test:cov || npm run -s test || true ) | tee "$LOG_DIR/test_coverage.txt" >/dev/null
# Coverage özetini kopar
grep -E 'Lines\s*:\s*[0-9]+' -A2 "$LOG_DIR/test_coverage.txt" || true

# --- Perf guard (mevcut API'ye vur; yoksa spawn et) ---
log "Perf guard (mümkünse mevcut API ile)"
if [ -f scripts/perf_guard.mjs ]; then
  PERF_URL="http://127.0.0.1:3002/health"
  # Önce mevcut ayakta mı?
  if curl -fsS "$PERF_URL" >/dev/null 2>&1; then
    PERF_SPAWN=0 PERF_URL="$PERF_URL" node scripts/perf_guard.mjs | tee "$LOG_DIR/perf.json" >/dev/null || true
  else
    # Spawn ederek ölç (ignored pathlere yazabilir, kodu değiştirmez)
    PERF_SPAWN=1 PERF_URL="$PERF_URL" node scripts/perf_guard.mjs | tee "$LOG_DIR/perf.json" >/dev/null || true
  fi
fi

# --- No-padding audit (rapor) ---
log "No-padding audit"
if [ -x scripts/no-padding-audit.sh ]; then
  scripts/no-padding-audit.sh . "$LOG_DIR/no_padding.log" || true
else
  echo "[skip] no-padding-audit yok" > "$LOG_DIR/no_padding.log"
fi

# --- Anti-fake guard (rapor) ---
log "Anti-fake guard"
if [ -x scripts/anti-fake-guard.sh ]; then
  scripts/anti-fake-guard.sh | tee "$LOG_DIR/anti_fake.txt" >/dev/null || true
else
  echo "[skip] anti-fake guard yok" > "$LOG_DIR/anti_fake.txt"
fi

# --- Compose SAFE (sadece ignored OUTDIR; tracked dosyaya dokunmaz) ---
log "Compose SAFE (OUTDIR=$AUDIT_OUT)"
if npm run -s compose:safe >/dev/null 2>&1; then
  (ls -la "$AUDIT_OUT" || true) > "$LOG_DIR/compose_out_listing.txt"
else
  echo "[warn] compose:safe çalışmadı (frozen olabilir)" > "$LOG_DIR/compose_out_listing.txt"
fi

# --- Dependency health (opsiyonel; network olabilir) ---
log "npm audit (rapor; fail etme)"
( npm audit --audit-level=high || true ) | tee "$LOG_DIR/npm_audit.txt" >/dev/null

# --- Son: Çalışma ağacı değişti mi? (tracked) ---
log "Post-flight: git cleanliness check"
git status --porcelain=v1 > "$LOG_DIR/git_status_after.txt"
if ! diff -u "$LOG_DIR/git_status_before.txt" "$LOG_DIR/git_status_after.txt" >/dev/null; then
  log "ERROR: Tracked working tree changed during audit (beklenmiyordu)."
  log "No mutation policy gereği betik FAIL veriyor (fix yapılmayacak)."
  exit 3
fi

# --- Markdown özet raporu üret ---
log "Build markdown report"
{
  echo "# GENESIS – Read-Only Audit (TS=$TS)"
  echo
  echo "## Repo"
  cat "$LOG_DIR/repo_meta.txt"
  echo
  echo "## Files"
  cat "$LOG_DIR/filecounts.txt" || true
  echo
  echo "### Biggest tracked files"
  sed -n '1,20p' "$LOG_DIR/top_big_files.txt" || true
  echo
  echo "## Lint Summary"
  grep -E "error|warning" "$LOG_DIR/eslint.txt" | tail -n 50 || echo "lint OK/empty"
  echo
  echo "## TypeCheck"
  if [ -s "$LOG_DIR/tsc.txt" ]; then tail -n 80 "$LOG_DIR/tsc.txt"; else echo "tsc clean"; fi
  echo
  echo "## Tests & Coverage"
  sed -n '1,120p' "$LOG_DIR/test_coverage.txt" || true
  echo
  echo "## Perf Guard"
  if [ -f "$LOG_DIR/perf.json" ]; then cat "$LOG_DIR/perf.json"; else echo "no perf data"; fi
  echo
  echo "## No-Padding Audit"
  sed -n '1,120p' "$LOG_DIR/no_padding.log" || true
  echo
  echo "## Anti-Fake Guard"
  sed -n '1,80p' "$LOG_DIR/anti_fake.txt" || true
  echo
  echo "## Compose SAFE (listing)"
  sed -n '1,80p' "$LOG_DIR/compose_out_listing.txt" || true
  echo
  echo "> Full raw logs under: $LOG_DIR/"
} > "$REPORT"

log "DONE. Report → $REPORT"