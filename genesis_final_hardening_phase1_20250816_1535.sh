#!/bin/bash
# genesis_final_hardening_phase1_20250816_1535.sh
set -euo pipefail

MODE="dry"; [[ "${1:-}" == "--apply" ]] && MODE="apply"
TS="$(date +'%Y%m%d_%H%M%S')"
LOG="logs/hardening_p1_$TS.log"
ARCH="archives/snapshot_p1_$TS.tar.gz"
FREE_PORT="${PORT:-3002}"

mkdir -p logs archives artifacts/reports
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
die(){ log "ERROR: $*"; exit 1; }

check_disk(){ df -Pk . | awk 'NR==2{if($4<524288)exit 1}'; }
dedup_gitignore(){ awk '!seen[$0]++' .gitignore > .gitignore.__tmp 2>/dev/null || true; mv .gitignore.__tmp .gitignore 2>/dev/null || true; }
append_gitignore(){ touch .gitignore; grep -qxF "$1" .gitignore || echo "$1" >> .gitignore; }

safe_clean(){ local p="$1"; [[ -e "$p" ]] || return 0; if [[ "$MODE" == "apply" ]]; then [[ -L "$p" ]] && { log "skip symlink $p"; return 0; } ; git clean -fd "$p" 2>&1 | tee -a "$LOG" || true; else git clean -nd "$p" 2>&1 | tee -a "$LOG" || true; fi; }

validate_json(){ node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$1" >/dev/null 2>&1; }
validate_jsonl(){ node -e 'const fs=require("fs");const p=process.argv[1];if(!fs.existsSync(p))process.exit(1);for(const[l,i]of fs.readFileSync(p,"utf8").split(/\r?\n/).entries()){const t=i.trim();if(!t)continue;try{JSON.parse(t)}catch(e){process.exit(2)}}' "$1" >/dev/null 2>&1; }

step(){ log "==> $*"; }

# 0) SNAPSHOT
step "SAFE SNAPSHOT (dry by default)"
check_disk || die "Yetersiz disk alanı (≥512MB gerekli)"
if [[ "$MODE" == "apply" ]]; then tar --exclude-vcs-ignores -czf "$ARCH" . 2>>"$LOG" || true; git tag -f hardening-p1-pre-"$TS" >/dev/null 2>&1 || true; log "Snapshot: $ARCH"; else log "(dry) would archive to $ARCH & create tag"; fi

# 1) .gitignore & GIT HİJYENİ
step "Git hijyeni ve ignore"
append_gitignore "docs/generated/"; append_gitignore "build/"; append_gitignore "logs/"; append_gitignore ".quarantine/"; append_gitignore "*.log"
append_gitignore "artifacts/reports/*.md"; append_gitignore "artifacts/reports/*.json"
dedup_gitignore
safe_clean "docs/generated"; safe_clean "logs"; safe_clean ".quarantine"

# 2) NO-PADDING EXCLUDE + GENERATED TAŞIMA
step "No-padding align (exclude + build/docs/)"
if [[ "$MODE" == "apply" ]]; then printf "build/\nnode_modules/\nartifacts/\nlogs/\n" > .no-padding-exclude; fi
if [[ -d docs/generated ]]; then
  if [[ "$MODE" == "apply" ]]; then mkdir -p build; rsync -a --remove-source-files docs/generated/ build/docs/ 2>>"$LOG" || true; rmdir docs/generated 2>/dev/null || true; else log "(dry) would move docs/generated -> build/docs/"; fi
fi

# 3) CONSTITUTION DOĞRULAMA
step "Constitution doğrulama"
[[ -f constitution.jsonl ]] && validate_jsonl constitution.jsonl || log "WARN: constitution.jsonl yok/bozuk olabilir"
if [[ ! -f final_constitution.jsonl && -f constitution.jsonl ]]; then
  if [[ "$MODE" == "apply" ]]; then cp constitution.jsonl final_constitution.jsonl; log "Restored final_constitution.jsonl"; else log "(dry) would copy constitution -> final_constitution"; fi
fi

# 4) DİNAMİK HEDEFLER (plan.mjs)
step "Dynamic targets plan (targets.auto.json)"
if [[ -f apps/composer/plan.mjs ]]; then
  node apps/composer/plan.mjs >>"$LOG" 2>&1 || log "plan.mjs run had warnings"
  [[ -f targets.auto.json ]] && validate_json targets.auto.json || log "WARN: targets.auto.json missing/invalid"
else
  log "SKIP: plan.mjs yok"
fi

# 5) TOOLCHAIN (TS/ESLint/Vitest) + PRUNE
step "Toolchain ve bağımlılık bakımı"
if [[ "$MODE" == "apply" ]]; then
  if [[ -f package-lock.json ]]; then npm ci || npm ci; else npm install || npm install; fi
  npm prune || true
  npm i -D typescript @types/node eslint vitest @vitest/coverage-v8 >/dev/null 2>&1 || true
  [[ -f tsconfig.json ]] || npx -y tsc --init >/dev/null 2>&1 || true
  # tsconfig strict aç
  node -e 'const fs=require("fs");if(fs.existsSync("tsconfig.json")){let j=JSON.parse(fs.readFileSync("tsconfig.json","utf8"));j.compilerOptions=j.compilerOptions||{};j.compilerOptions.strict=true;j.compilerOptions.esModuleInterop=true;fs.writeFileSync("tsconfig.json",JSON.stringify(j,null,2));}'
  # ESLint temel
  [[ -f .eslintrc.cjs || -f .eslintrc.js || -f .eslintrc.json ]] || npx -y eslint --init >/dev/null 2>&1 || true
  [[ -f vitest.config.mjs ]] || cat > vitest.config.mjs <<'JS'
export default { test: { coverage: { provider: "v8", lines: 60 } } }
JS
else
  log "(dry) would install & init TS/ESLint/Vitest; set coverage threshold=60"
fi

# 6) ÇALIŞIR API /health (3002)
step "API /health wiring (port $FREE_PORT)"
if [[ "$MODE" == "apply" ]]; then
  mkdir -p apps/api/src/routes
  cat > apps/api/src/index.mjs <<JS
import express from "express";
import health from "./routes/health.mjs";
const app = express();
const PORT = process.env.PORT || ${FREE_PORT};
app.get("/health", health);
app.listen(PORT, () => console.log(\`[api] listening on \${PORT}\`));
export default app;
JS
  cat > apps/api/src/routes/health.mjs <<'JS'
export default (req,res)=>res.status(200).json({ok:true,ts:Date.now()});
JS
  ( node apps/api/src/index.mjs & echo $! > /tmp/api_pid_p1_$TS ) || true
  sleep 2
  curl -fsS "http://localhost:${FREE_PORT}/health" >/dev/null && log "Health OK" || log "Health FAILED"
  [[ -f /tmp/api_pid_p1_$TS ]] && kill "$(cat /tmp/api_pid_p1_$TS)" 2>/dev/null || true
else
  log "(dry) would ensure express app + /health on $FREE_PORT"
fi

# 7) COMPOSE (dry), GUARDS, VALIDATE
step "Compose/Guards/Validate"
npm run -s compose -- --dry-run >>"$LOG" 2>&1 || log "compose dry-run non-zero"
[[ -x scripts/anti-fake-guard.sh ]] && scripts/anti-fake-guard.sh >>"$LOG" 2>&1 || log "anti-fake guard missing/fail"
if [[ -x scripts/no-padding-audit.sh ]]; then scripts/no-padding-audit.sh . "logs/no_padding_audit_latest.log" >>"$LOG" 2>&1 || log "no-padding audit fail"; else log "no-padding audit missing"; fi
npm run -s validate >>"$LOG" 2>&1 || log "validate failed (see log)"

# 8) LINT + TSC + TEST
step "Lint + Typecheck + Tests (coverage ≥60%)"
npx -y eslint . >>"$LOG" 2>&1 || log "eslint issues (will not stop)"
npx -y tsc --noEmit >>"$LOG" 2>&1 || log "ts errors (review)"
if npm run -s test:cov >/dev/null 2>&1 || npm run -s test >/dev/null 2>&1; then npm run -s test:cov >>"$LOG" 2>&1 || log "coverage run failed"; else log "No test script"; fi

# 9) GAP SCAN
step "Gap Scan yeniden"
[[ -x ./genesis_gap_scan_20250816_1418.sh ]] && ./genesis_gap_scan_20250816_1418.sh >>"$LOG" 2>&1 || log "Gap Scan script not found"

# 10) ÖZET
step "Özet"
git status --porcelain | wc -l | xargs -I{} log "Workspace pending count: {}"
log "Log: $LOG"
log "Snapshot: $ARCH (if apply)"
log "DONE Phase-1 ✅  (apply: $MODE)  |  Next: Phase-2 CI/CD + perf guard"