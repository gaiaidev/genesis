#!/usr/bin/env bash
# genesis_gap_scan_20250816_1418.sh
set -euo pipefail

TS="$(date +'%Y%m%d_%H%M%S')"
ART_DIR="artifacts/reports"
LOG_DIR="logs"
OUT_JSON="$ART_DIR/genesis_gap_report_${TS}.json"
OUT_MD="$ART_DIR/genesis_gap_summary_${TS}.md"
CLAUDE_MD="$ART_DIR/claude_gap_review_${TS}.md"

mkdir -p "$ART_DIR" "$LOG_DIR"

echo "[*] Genesis Gap Scan started @ $TS"

# -------- Meta ----------
REPO_ROOT="$(pwd)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'no-git')"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"
GIT_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
NODE_VER="$(node -v 2>/dev/null || echo 'node-missing')"
NPM_VER="$(npm -v 2>/dev/null || echo 'npm-missing')"
OS="$(uname -a 2>/dev/null || echo 'unknown-os')"

# util: mark check
checks_json="[]"
append_check () {
  # $1=id  $2=status ok|warn|fail  $3=summary  $4=evidence_path
  local id="$1"; local status="$2"; local summary="$3"; local ev="${4:-""}"
  checks_json="$(node -e "let a=$checks_json; a.push({id:'$id',status:'$status',summary:\`$summary\`,evidence:'$ev'}); console.log(JSON.stringify(a))")"
}

# -------- Çekirdek dosyalar ----------
missing=()
for f in apps/composer/compose.mjs constitution.jsonl Makefile package.json; do
  [[ -e "$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  append_check "core.files" "fail" "Eksik çekirdek dosyalar: ${missing[*]}" ""
else
  append_check "core.files" "ok" "Tüm çekirdek dosyalar mevcut" ""
fi

# -------- Plan / Targets ----------
PLAN_LOG="$LOG_DIR/plan_${TS}.log"
if [[ -f apps/composer/plan.mjs ]]; then
  if node apps/composer/plan.mjs >"$PLAN_LOG" 2>&1; then
    if [[ -f targets.auto.json ]]; then
      append_check "plan.generate" "ok" "targets.auto.json üretildi" "$PLAN_LOG"
    else
      append_check "plan.generate" "warn" "plan.mjs çalıştı ama targets.auto.json yok" "$PLAN_LOG"
    fi
  else
    append_check "plan.generate" "fail" "plan.mjs hata verdi" "$PLAN_LOG"
  fi
else
  append_check "plan.generate" "warn" "apps/composer/plan.mjs yok, dinamik hedefler kapalı" ""
fi

# -------- Compose Dry --------
COMP_LOG="$LOG_DIR/compose_${TS}.log"
if grep -q "\"compose\"" package.json 2>/dev/null; then
  if npm run -s compose -- --dry-run >"$COMP_LOG" 2>&1 || npm run -s compose >"$COMP_LOG" 2>&1; then
    append_check "compose.run" "ok" "npm run compose başarılı" "$COMP_LOG"
  else
    append_check "compose.run" "fail" "npm run compose hata verdi" "$COMP_LOG"
  fi
else
  append_check "compose.run" "warn" "package.json script 'compose' yok" ""
fi

# -------- Anti-Fake Guard --------
AF_LOG="$LOG_DIR/anti_fake_${TS}.log"
if [[ -x scripts/anti-fake-guard.sh ]]; then
  if scripts/anti-fake-guard.sh >"$AF_LOG" 2>&1; then
    append_check "guard.anti_fake" "ok" "Anti-Fake guard geçti" "$AF_LOG"
  else
    append_check "guard.anti_fake" "fail" "Anti-Fake guard FAILED" "$AF_LOG"
  fi
else
  append_check "guard.anti_fake" "warn" "scripts/anti-fake-guard.sh bulunamadı" ""
fi

# -------- No-Padding Audit --------
NP_LOG="$LOG_DIR/no_padding_${TS}.log"
if [[ -x scripts/no-padding-audit-v2.sh ]]; then
  if scripts/no-padding-audit-v2.sh . "$NP_LOG" >/dev/null 2>&1; then
    append_check "guard.no_padding" "ok" "No-Padding audit OK" "$NP_LOG"
  elif [[ -x scripts/no-padding-audit.sh ]]; then
    if scripts/no-padding-audit.sh . "$NP_LOG" >/dev/null 2>&1; then
      append_check "guard.no_padding" "ok" "No-Padding audit OK (v1)" "$NP_LOG"
    else
      append_check "guard.no_padding" "fail" "No-Padding audit FAILED (detay logda)" "$NP_LOG"
    fi
  else
    append_check "guard.no_padding" "fail" "No-Padding audit FAILED" "$NP_LOG"
  fi
else
  append_check "guard.no_padding" "warn" "no-padding audit yok (önerilir)" ""
fi

# -------- Validate --------
VAL_LOG="$LOG_DIR/validate_${TS}.log"
if grep -q "\"validate\"" package.json 2>/dev/null; then
  if timeout 30 npm run -s validate >"$VAL_LOG" 2>&1; then
    append_check "validate.run" "ok" "npm run validate başarılı" "$VAL_LOG"
  else
    append_check "validate.run" "fail" "validate FAILED veya timeout" "$VAL_LOG"
  fi
else
  append_check "validate.run" "warn" "package.json script 'validate' yok" ""
fi

# -------- Typecheck --------
TC_LOG="$LOG_DIR/typecheck_${TS}.log"
if [[ -f tsconfig.json ]]; then
  if npx -y tsc --noEmit >"$TC_LOG" 2>&1; then
    append_check "types.ts" "ok" "TypeScript typecheck OK" "$TC_LOG"
  else
    append_check "types.ts" "fail" "TypeScript typecheck hataları" "$TC_LOG"
  fi
else
  append_check "types.ts" "warn" "tsconfig.json yok" ""
fi

# -------- Lint --------
LINT_LOG="$LOG_DIR/lint_${TS}.log"
if [[ -f .eslintrc.json ]] || [[ -f .eslintrc.js ]]; then
  if npx -y eslint . --max-warnings 0 >"$LINT_LOG" 2>&1; then
    append_check "lint.eslint" "ok" "ESLint temiz" "$LINT_LOG"
  else
    append_check "lint.eslint" "fail" "ESLint sorunları" "$LINT_LOG"
  fi
else
  append_check "lint.eslint" "warn" "ESLint config yok" ""
fi

# -------- Test --------
TEST_LOG="$LOG_DIR/test_${TS}.log"
if grep -q "\"test\"" package.json 2>/dev/null; then
  if timeout 60 npm run -s test >"$TEST_LOG" 2>&1; then
    append_check "tests.run" "ok" "Testler geçti" "$TEST_LOG"
  else
    append_check "tests.run" "fail" "Testler FAILED veya timeout" "$TEST_LOG"
  fi
else
  append_check "tests.run" "warn" "Test script'i yok" ""
fi

# -------- Coverage --------
COV_LOG="$LOG_DIR/coverage_${TS}.log"
if grep -q "\"test:cov\"" package.json 2>/dev/null; then
  if timeout 60 npm run -s test:cov >"$COV_LOG" 2>&1; then
    # Coverage oranını kontrol et
    if [[ -f coverage/coverage-summary.json ]]; then
      COV_LINES=$(node -e "let c=require('./coverage/coverage-summary.json'); console.log(Math.round(c.total.lines.pct))" 2>/dev/null || echo "0")
      if [[ "$COV_LINES" -ge 70 ]]; then
        append_check "tests.coverage" "ok" "Coverage %${COV_LINES} (>70%)" "$COV_LOG"
      else
        append_check "tests.coverage" "warn" "Coverage %${COV_LINES} (<70%)" "$COV_LOG"
      fi
    else
      append_check "tests.coverage" "ok" "Coverage test çalıştı" "$COV_LOG"
    fi
  else
    append_check "tests.coverage" "fail" "Coverage test FAILED" "$COV_LOG"
  fi
else
  append_check "tests.coverage" "warn" "test:cov script yok" ""
fi

# -------- Perf Smoke (opsiyonel) --------
PERF_LOG="$LOG_DIR/perf_smoke_${TS}.log"
if [[ -f apps/composer/last_mile_check.mjs ]]; then
  if node apps/composer/last_mile_check.mjs >"$PERF_LOG" 2>&1; then
    append_check "perf.smoke" "ok" "last_mile_check OK" "$PERF_LOG"
  else
    append_check "perf.smoke" "fail" "last_mile_check FAILED" "$PERF_LOG"
  fi
else
  append_check "perf.smoke" "warn" "last_mile_check.mjs yok" ""
fi

# -------- Security: Secrets --------
SEC_LOG="$LOG_DIR/secrets_${TS}.log"
if [[ -x scripts/scan-secrets.sh ]] || [[ -x tools/scan-secrets.sh ]]; then
  SCAN_SCRIPT=$(find scripts tools -name "*scan-secrets*" -type f -executable | head -1)
  if $SCAN_SCRIPT >"$SEC_LOG" 2>&1; then
    append_check "security.secrets" "ok" "Secret scan temiz" "$SEC_LOG"
  else
    append_check "security.secrets" "fail" "Secret scan FAILED (muhtemel leak)" "$SEC_LOG"
  fi
else
  append_check "security.secrets" "warn" "Secret scanner yok" ""
fi

# -------- Dependency Audit --------
AUDIT_LOG="$LOG_DIR/npm_audit_${TS}.log"
if npm audit --json >"$AUDIT_LOG" 2>/dev/null; then
  HIGH="$(grep -o '"severity":"high"' "$AUDIT_LOG" | wc -l | tr -d ' ')"
  CRIT="$(grep -o '"severity":"critical"' "$AUDIT_LOG" | wc -l | tr -d ' ')"
  if (( CRIT>0 )); then
    append_check "deps.audit" "fail" "npm audit: critical=$CRIT high=$HIGH" "$AUDIT_LOG"
  elif (( HIGH>0 )); then
    append_check "deps.audit" "warn" "npm audit: high=$HIGH" "$AUDIT_LOG"
  else
    append_check "deps.audit" "ok" "npm audit temiz" "$AUDIT_LOG"
  fi
else
  append_check "deps.audit" "warn" "npm audit çalışmadı (izin/bağlantı?)" ""
fi

# -------- File Count/Structure --------
FILE_LOG="$LOG_DIR/files_${TS}.log"
{
  echo "=== File Structure Analysis ==="
  echo "Total files: $(find . -type f -not -path "*/node_modules/*" -not -path "*/.git/*" | wc -l)"
  echo "JS/TS files: $(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.mjs" \) -not -path "*/node_modules/*" | wc -l)"
  echo "Generated docs: $(find docs/generated -type f 2>/dev/null | wc -l)"
  echo "Templates: $(find genesis_template -type f 2>/dev/null | wc -l)"
  echo ""
  echo "=== Top directories by file count ==="
  for dir in apps constitution docs genesis_template; do
    if [[ -d "$dir" ]]; then
      echo "$dir: $(find "$dir" -type f | wc -l) files"
    fi
  done
} > "$FILE_LOG"
append_check "structure.files" "ok" "File structure analyzed" "$FILE_LOG"

# -------- Boyut/Şişme --------
DU_LOG="$LOG_DIR/size_${TS}.log"
{
  echo "# Disk Kullanımı (ilk 20)"
  du -sh ./* 2>/dev/null | sort -hr | head -n 20
  echo ""
  echo "# node_modules boyutu"
  du -sh node_modules 2>/dev/null || echo "node_modules: not found"
} > "$DU_LOG"
append_check "size.disk" "ok" "Boyut özeti hazır" "$DU_LOG"

# -------- Git durumu --------
GIT_LOG="$LOG_DIR/git_${TS}.log"
{
  echo "branch: $GIT_BRANCH"
  echo "commit: $GIT_COMMIT"
  echo "dirty_count: $GIT_DIRTY"
  echo ""
  echo "=== Recent commits ==="
  git log --oneline -10 2>/dev/null || echo "no git log"
  echo ""
  echo "=== Changed files ==="
  git status --porcelain 2>/dev/null || echo "no changes"
} > "$GIT_LOG"
if [[ "$GIT_DIRTY" -gt 20 ]]; then
  append_check "git.state" "fail" "Çok fazla uncommitted değişiklik ($GIT_DIRTY)" "$GIT_LOG"
elif [[ "$GIT_DIRTY" -gt 0 ]]; then
  append_check "git.state" "warn" "Çalışma alanı kirli ($GIT_DIRTY değişiklik)" "$GIT_LOG"
else
  append_check "git.state" "ok" "Çalışma alanı temiz" "$GIT_LOG"
fi

# -------- JSON raporunu yaz ----------
cat > "$OUT_JSON" <<JSON
{
  "meta": {
    "timestamp": "$TS",
    "repo": "$REPO_ROOT",
    "git_branch": "$GIT_BRANCH",
    "git_commit": "$GIT_COMMIT",
    "git_dirty_count": $GIT_DIRTY,
    "node": "$NODE_VER",
    "npm": "$NPM_VER",
    "os": "$OS"
  },
  "checks": $checks_json
}
JSON

# -------- Özet MD ----------
TOTAL=$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); console.log(j.checks.length)")
OKS=$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); console.log(j.checks.filter(c=>c.status==='ok').length)")
FAILS=$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); console.log(j.checks.filter(c=>c.status==='fail').length)")
WARNS=$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); console.log(j.checks.filter(c=>c.status==='warn').length)")

cat > "$OUT_MD" <<MD
# Genesis Gap Summary – $TS

- **Repo:** \`$REPO_ROOT\`
- **Git:** \`$GIT_BRANCH@$GIT_COMMIT\` (dirty: $GIT_DIRTY)
- **Node/NPM:** \`$NODE_VER / $NPM_VER\`
- **OS:** \`$OS\`

## Overall Status

| Metric | Count | Status |
|--------|-------|--------|
| Total Checks | $TOTAL | - |
| ✅ Passed | $OKS | $([ "$OKS" -eq "$TOTAL" ] && echo "🎉 Perfect!" || echo "⚠️") |
| ❌ Failed | $FAILS | $([ "$FAILS" -eq 0 ] && echo "✅" || echo "🔴 Needs Fix") |
| ⚠️ Warnings | $WARNS | $([ "$WARNS" -eq 0 ] && echo "✅" || echo "🟡 Review") |

## Critical Issues (FAIL)
$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); let fails=j.checks.filter(c=>c.status==='fail'); if(fails.length===0) console.log('None! 🎉'); else fails.forEach(c=>console.log('- **['+c.id+']** '+c.summary + (c.evidence? ' → \`'+c.evidence+'\`':'')))")

## Warnings (WARN)
$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); let warns=j.checks.filter(c=>c.status==='warn'); if(warns.length===0) console.log('None! ✅'); else warns.forEach(c=>console.log('- **['+c.id+']** '+c.summary + (c.evidence? ' → \`'+c.evidence+'\`':'')))")

## All Checks Summary
$(node -e "let r=require('fs').readFileSync('$OUT_JSON','utf8'); let j=JSON.parse(r); j.checks.forEach(c=>{ let icon=c.status==='ok'?'✅':c.status==='warn'?'⚠️':'❌'; console.log(icon+' **'+c.id+'** → '+c.summary)})")

---
> **Full JSON Report:** \`$OUT_JSON\`
> **Generated:** $(date)
MD

# -------- Claude için hazır prompt ----------
cat > "$CLAUDE_MD" <<'HDR'
# Claude – Genesis Gap Review Request

Below is an automated "Gap Scan" output for the Genesis project. Please:

1. **Identify the top 5-7 critical issues** in priority order
2. For each issue, provide:
   - **Root cause analysis** 
   - **Specific, actionable fix** (with code/commands if applicable)
   - **Success criteria** to verify the fix worked
3. Suggest an **implementation order** considering dependencies
4. Provide a **risk assessment** if these issues remain unfixed

## Context
This is the Genesis framework - a constitution-based code generation system that aims to produce enterprise-grade applications with built-in quality gates and compliance checks.

HDR

{
  echo
  echo "## Human-Readable Summary"
  echo
  echo '```markdown'
  cat "$OUT_MD"
  echo '```'
  echo
  echo "## Machine-Readable Report (JSON)"
  echo
  echo '```json'
  cat "$OUT_JSON"
  echo '```'
  echo
  echo "## Request"
  echo "Based on the above scan results, please provide:"
  echo "1. Prioritized action items"
  echo "2. Specific fixes with verification steps"
  echo "3. Estimated effort (quick/medium/complex) for each fix"
  echo "4. Any architectural concerns or recommendations"
} >> "$CLAUDE_MD"

echo ""
echo "========================================="
echo "       GENESIS GAP SCAN COMPLETE        "
echo "========================================="
echo "📊 JSON Report : $OUT_JSON"
echo "📝 Summary     : $OUT_MD"
echo "🤖 Claude Ready: $CLAUDE_MD"
echo ""
echo "Status: ✅ OK: $OKS | ⚠️ WARN: $WARNS | ❌ FAIL: $FAILS"
echo "========================================="

if [[ "$FAILS" -gt 0 ]]; then
  echo "⚠️  Critical issues detected! Review $OUT_MD for details."
  exit 1
else
  echo "✅ No critical failures detected."
  exit 0
fi