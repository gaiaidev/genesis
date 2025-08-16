#!/usr/bin/env bash
# genesis_gap_fix_orchestrator_v2_20250816_1510.sh
set -euo pipefail

MODE="dry"             # default: dry-run
[[ "${1:-}" == "--apply" ]] && MODE="apply"

TS="$(date +'%Y%m%d_%H%M%S')"
EVID="evidence/gap_fix_$TS"
LOG="logs/gap_fix_$TS.log"
ARCH="archives/snapshot_$TS.tar.gz"

mkdir -p "$(dirname "$EVID")" logs archives artifacts/reports || true
touch "$LOG"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
die(){ log "ERROR: $*"; exit 1; }

# =============== UTILITIES ===============

need_disk_kb=524288   # ~512MB
check_disk(){
  local avail_kb
  avail_kb=$(df -Pk . | awk 'NR==2{print $4}')
  [[ "${avail_kb:-0}" -ge "$need_disk_kb" ]] || die "Yetersiz disk alanı (gereken ≥ ${need_disk_kb}KB)"
}

dedup_gitignore_lines(){
  local tmp=".gitignore.__tmp__$TS"
  awk '!seen[$0]++' .gitignore > "$tmp" 2>/dev/null || true
  mv "$tmp" .gitignore 2>/dev/null || true
}

append_gitignore_unique(){
  local line="$1"
  touch .gitignore
  grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
}

safe_clean_path(){
  # dry-run ile göster, apply'da sadece path bir symlink değilse ve repo içindeyse temizle
  local p="$1"
  [[ -e "$p" ]] || return 0
  if [[ "$MODE" == "apply" ]]; then
    if [[ -L "$p" ]]; then
      log "Skip symlink: $p"
    else
      git clean -fd "$p" 2>&1 | tee -a "$LOG" || true
    fi
  else
    git clean -nd "$p" 2>&1 | tee -a "$LOG" || true
  fi
}

validate_json_file(){
  # $1 = path, strict JSON
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$1" >/dev/null 2>&1
}

validate_jsonl_file(){
  # $1 = path, each non-empty trimmed line must be valid JSON
  node -e '
    const fs=require("fs");
    const p=process.argv[1];
    if(!fs.existsSync(p)){process.exit(1)}
    const lines=fs.readFileSync(p,"utf8").split(/\r?\n/);
    for(const [i,l] of lines.entries()){
      const t=l.trim(); if(!t) continue;
      try{ JSON.parse(t) }catch(e){ console.error("Invalid JSONL at line", i+1); process.exit(2); }
    }' "$1" >/dev/null 2>&1
}

choose_free_port(){
  # echo first free port in [3001..3010]
  local p
  for p in {3001..3010}; do
    if ! lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p "; then
      echo "$p"; return 0
    fi
  done
  echo 3001
}

wait_for_health(){
  local url="$1" retries=15
  while ((retries-- > 0)); do
    if curl -fsS "$url" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

npm_install_smart(){
  if [[ "$MODE" != "apply" ]]; then
    log "(dry) would run: npm ci (if lock) or npm install"
    return 0
  fi
  if [[ -f package-lock.json ]]; then
    npm ci || npm ci || die "npm ci failed"
  else
    npm install || npm install || die "npm install failed"
  fi
}

progress_total=12
progress_curr=0
step(){ progress_curr=$((progress_curr+1)); log "[$progress_curr/$progress_total] $*"; }

# Rollback (yalnızca apply modda mantıklı)
rollback(){
  [[ "$MODE" == "apply" ]] || return 0
  if [[ -f "$ARCH" ]]; then
    log "Rolling back from $ARCH ..."
    tar -xzf "$ARCH" . 2>>"$LOG" || true
  fi
  if git rev-parse --verify "gapfix-pre-$TS" >/dev/null 2>&1; then
    git reset --hard "gapfix-pre-$TS" >>"$LOG" 2>&1 || true
  fi
  log "Rollback completed."
}
trap 'rollback' ERR INT

# =============== TASKS ===============

snapshot(){
  step "SAFE SNAPSHOT (disk alanı kontrolü)"
  check_disk
  if [[ "$MODE" == "apply" ]]; then
    tar --exclude-vcs-ignores -czf "$ARCH" . 2>>"$LOG" || true
    if git rev-parse --short HEAD >/dev/null 2>&1; then
      git tag -f gapfix-pre-"$TS" >>"$LOG" 2>&1 || true
    fi
    [[ -f "$ARCH" ]] || die "Snapshot failed"
  else
    log "(dry) would create snapshot: $ARCH & git tag gapfix-pre-$TS"
  fi
}

git_hygiene(){
  step "GIT HYGIENE (.gitignore tekilleştirme + allowlist clean)"
  touch .gitignore
  append_gitignore_unique "docs/generated/"
  append_gitignore_unique "build/"
  append_gitignore_unique "logs/"
  append_gitignore_unique ".quarantine/"
  append_gitignore_unique "*.log"
  append_gitignore_unique "artifacts/reports/*.md"
  append_gitignore_unique "artifacts/reports/*.json"
  dedup_gitignore_lines

  log "Git status (exclude-standard):"
  git -c core.quotepath=false status --porcelain --ignored --untracked-files=all 2>/dev/null | head -20 | tee -a "$LOG" || true

  safe_clean_path "docs/generated"
  safe_clean_path "logs"
  safe_clean_path ".quarantine"
}

fix_constitution(){
  step "CONSTITUTION doğrulama/restore"
  if [[ -f constitution.jsonl ]]; then
    if ! validate_jsonl_file constitution.jsonl; then
      die "constitution.jsonl invalid JSONL"
    fi
  fi
  if [[ ! -f final_constitution.jsonl && -f constitution.jsonl ]]; then
    if [[ "$MODE" == "apply" ]]; then
      cp constitution.jsonl final_constitution.jsonl
      log "Restored final_constitution.jsonl from constitution.jsonl"
      git add final_constitution.jsonl >/dev/null 2>&1 || true
    else
      log "(dry) would copy constitution.jsonl -> final_constitution.jsonl"
    fi
  fi
  [[ -f final_constitution.jsonl ]] || log "WARN: final_constitution.jsonl missing"
}

align_guards(){
  step "GUARDS hizalama (no-padding exclude + build/docs/)"
  if [[ "$MODE" == "apply" ]]; then
    printf "build/\nnode_modules/\nartifacts/\nlogs/\n" > .no-padding-exclude
  else
    log "(dry) would write .no-padding-exclude"
  fi
  if [[ -d docs/generated ]]; then
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p build
      rsync -a --remove-source-files docs/generated/ build/docs/ 2>>"$LOG" || log "rsync not available, using mv"
      if [[ -d docs/generated ]]; then
        mv docs/generated/* build/docs/ 2>/dev/null || true
        rmdir docs/generated 2>/dev/null || true
      fi
      log "Moved docs/generated -> build/docs/"
    else
      log "(dry) would move docs/generated -> build/docs/"
    fi
  fi
}

parallel_plan_and_tooling(){
  step "PARALEL: dynamic targets & tooling"
  (
    if [[ -f apps/composer/plan.mjs ]]; then
      node apps/composer/plan.mjs >>"$LOG" 2>&1 || true
      if [[ -f targets.auto.json ]]; then
        validate_json_file targets.auto.json || log "WARN: targets.auto.json invalid"
      else
        log "WARN: targets.auto.json not produced"
      fi
    else
      log "WARN: plan.mjs not found"
    fi
  ) & PID1=$!

  (
    npm_install_smart
    if [[ "$MODE" == "apply" ]]; then
      npm i -D typescript @types/node eslint vitest @vitest/coverage-v8 >/dev/null 2>&1 || true
      [[ -f tsconfig.json ]] || npx -y tsc --init >/dev/null 2>&1 || true
      [[ -f .eslintrc.cjs || -f .eslintrc.js || -f .eslintrc.json ]] || npx -y eslint --init >/dev/null 2>&1 || true
      [[ -f vitest.config.mjs ]] || cat > vitest.config.mjs <<'JS'
export default { test: { coverage: { provider: "v8", lines: 50 } } }
JS
    else
      log "(dry) would ensure TS/ESLint/Vitest"
    fi
  ) & PID2=$!

  wait $PID1 $PID2 || log "Parallel phase had issues"
}

ensure_health_api(){
  step "HEALTH endpoint ve port seçimi"
  local PORT; PORT="$(choose_free_port)"
  if [[ "$MODE" == "apply" ]]; then
    mkdir -p apps/api/src/routes
    cat > apps/api/src/index.mjs <<JS
import express from "express";
const app = express();
const PORT = process.env.PORT || ${PORT};
app.get("/health", (req, res) => res.status(200).json({ ok: true, version: "1.0.0", uptimeSec: process.uptime(), now: Date.now() }));
app.listen(PORT, () => console.log(\`[api] listening on \${PORT}\`));
export default app;
JS
    ( timeout 5 node apps/api/src/index.mjs & echo $! > /tmp/api_pid_$TS ) 2>/dev/null || true
    sleep 2
    if wait_for_health "http://localhost:${PORT}/health"; then
      log "Health OK on :${PORT}"
    else
      log "Health FAILED on :${PORT}"
    fi
    [[ -f /tmp/api_pid_$TS ]] && kill "$(cat /tmp/api_pid_$TS)" 2>/dev/null || true
    rm -f /tmp/api_pid_$TS
  else
    log "(dry) would write express app & /health on port $PORT"
  fi
}

run_compose_and_guards(){
  step "COMPOSE + GUARDS + VALIDATE"
  if grep -q "\"compose\"" package.json 2>/dev/null; then
    npm run -s compose -- --dry-run >>"$LOG" 2>&1 || log "compose dry-run non-zero (check logs)"
  fi
  [[ -x scripts/anti-fake-guard.sh ]] && scripts/anti-fake-guard.sh >>"$LOG" 2>&1 || log "anti-fake guard missing/fail"
  if [[ -x scripts/no-padding-audit-v2.sh ]]; then
    scripts/no-padding-audit-v2.sh . >>"$LOG" 2>&1 || log "no-padding audit fail"
  elif [[ -x scripts/no-padding-audit.sh ]]; then
    scripts/no-padding-audit.sh . "logs/no_padding_audit_latest.log" >>"$LOG" 2>&1 || log "no-padding audit fail"
  else
    log "no-padding audit missing"
  fi
  if grep -q "\"validate\"" package.json 2>/dev/null; then
    timeout 30 npm run -s validate >>"$LOG" 2>&1 || log "validate failed (see log)"
  fi
}

tests_and_cov(){
  step "TS check + ESLint + Tests (≥50%)"
  if [[ -f tsconfig.json ]]; then
    npx -y tsc --noEmit >>"$LOG" 2>&1 || log "tsc errors"
  fi
  if [[ -f .eslintrc.json || -f .eslintrc.js || -f .eslintrc.cjs ]]; then
    npx -y eslint . --max-warnings 10 >>"$LOG" 2>&1 || log "eslint issues"
  fi
  if grep -q "\"test:cov\"" package.json 2>/dev/null; then
    timeout 60 npm run -s test:cov >>"$LOG" 2>&1 || log "coverage run failed/timeout"
  elif grep -q "\"test\"" package.json 2>/dev/null; then
    timeout 60 npm run -s test >>"$LOG" 2>&1 || log "test run failed/timeout"
  else
    log "No test script"
  fi
}

rerun_gap_scan(){
  step "GAP SCAN tekrar (kanıt üretimi)"
  if [[ -x ./genesis_gap_scan_20250816_1418.sh ]]; then
    ./genesis_gap_scan_20250816_1418.sh >>"$LOG" 2>&1 || true
  else
    log "Gap Scan script not found; skipping."
  fi
}

summary(){
  step "ÖZET"
  log "========================================="
  log "Mode: $MODE"
  log "Snapshot: $ARCH"
  log "Log: $LOG"
  
  local git_count
  git_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  log "Git uncommitted files: $git_count"
  
  # Success metrics
  local ok fail warn
  ok=$(grep -c "✅\|OK\|\[OK\]" "$LOG" 2>/dev/null || echo 0)
  fail=$(grep -c "❌\|FAIL\|ERROR" "$LOG" 2>/dev/null || echo 0)
  warn=$(grep -c "⚠️\|WARN" "$LOG" 2>/dev/null || echo 0)
  
  log "Results: ✅ OK: $ok | ⚠️ WARN: $warn | ❌ FAIL: $fail"
  log "========================================="
}

# =============== ORCHESTRATION ===============
log "========================================="
log "GENESIS GAP FIX ORCHESTRATOR V2"
log "Mode=$MODE  |  Start TS=$TS"
log "========================================="

snapshot
git_hygiene
fix_constitution
align_guards
parallel_plan_and_tooling
ensure_health_api
run_compose_and_guards
tests_and_cov
rerun_gap_scan
summary

log "DONE ✅  (To APPLY changes, rerun with: $0 --apply)"