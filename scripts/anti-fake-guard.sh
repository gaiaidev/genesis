#!/usr/bin/env bash
# ULTRA AGGRESSIVE fake pattern detection - v2
set -euo pipefail

echo "=== ULTRA HARD Anti-Fake Guard v2 ==="

# Tüm dizinleri tara (exclusions: node_modules, .git, release assets, tools, cleaned patterns)
BAD=$(find . -type f \( -name "*.sh" -o -name "*.js" -o -name "*.mjs" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" \) \
  -not -path "./node_modules/*" \
  -not -path "./.git/*" \
  -not -path "./dist/*" \
  -not -path "./build/*" \
  -not -path "./release/payment-starter/frontend/assets/*" \
  -not -path "./tools/*" \
  -not -path "./evidence/*" \
  -not -path "./ci/*" \
  -not -path "./.genesis/*" \
  -not -path "./proof/*" \
  -not -path "./constitution/*" \
  -exec grep -HnE 'echo\s+["'\'']?\{.*\}["'\'']?\s*>\s*[^#]*\.json|printf\s+["'\'']?\{.*\}["'\'']?\s*>\s*[^#]*\.json|cat\s+>\s*[^#]*\.json\s*<<' {} \; 2>/dev/null | \
  grep -v "# \[CLEANED" | \
  grep -v "^#" || true)

# JSON.stringify bypass patterns (exclude test files)
STRINGIFY_ABUSE=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.mjs" \) \
  -not -path "./node_modules/*" \
  -not -path "./.git/*" \
  -not -path "./release/*" \
  -not -path "./tools/*" \
  -not -path "./tests/*" \
  -not -path "./e2e/*" \
  -exec grep -HnE 'JSON\.stringify\([^)]*success[^)]*true[^)]*\)' {} \; 2>/dev/null || true)

# Hardcoded patterns (very selective - only production code)
HARDCODED=$(find . -type f \( -name "*.sh" -o -name "*.js" -o -name "*.ts" \) \
  -not -path "./node_modules/*" \
  -not -path "./.git/*" \
  -not -path "./release/*" \
  -not -path "./tools/*" \
  -not -path "./scripts/*test*.sh" \
  -not -path "./scripts/*audit*.sh" \
  -not -path "./genesis_*.sh" \
  -not -path "./*test*.sh" \
  -not -path "./tests/*" \
  -not -path "./e2e/*" \
  -exec grep -HnE 'coverage\s*=\s*\"[89][0-9]\"|coverage\s*=\s*\"100\"' {} \; 2>/dev/null | \
  grep -v "MIN_COVERAGE" | \
  grep -v "# \[CLEANED" || true)

if [[ -n "${BAD}${STRINGIFY_ABUSE}${HARDCODED}" ]]; then
  echo "❌ ULTRA FAIL: Fake patterns detected!"
  [[ -n "$BAD" ]] && echo -e "Fake JSON:\n$BAD"
  [[ -n "$STRINGIFY_ABUSE" ]] && echo -e "Stringify abuse:\n$STRINGIFY_ABUSE"
  [[ -n "$HARDCODED" ]] && echo -e "Hardcoded coverage:\n$HARDCODED"
  exit 1
fi

echo "✅ ULTRA CLEAN: No fake patterns"