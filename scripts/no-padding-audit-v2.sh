#!/usr/bin/env bash
# No-Padding Audit V2: Enhanced içerik kalitesi kontrolü
set -euo pipefail

ROOT="${1:-.}"
OUT="${2:-logs/no_padding_audit_$(date +%Y%m%d_%H%M%S).log}"
THRESH_UNIQUE=0.70   # benzersiz satır oranı eşiği
MAX_FILLERS=3        # filler ifadelere izin verilen üst sınır
FAIL_COUNT=0
PASS_COUNT=0
TOTAL_COUNT=0

echo "=======================================" | tee "$OUT"
echo "    GENESIS QUALITY AUDIT REPORT      " | tee -a "$OUT"
echo "=======================================" | tee -a "$OUT"
echo "Time: $(date -Is)" | tee -a "$OUT"
echo "Root: $ROOT" | tee -a "$OUT"
echo "Thresholds:" | tee -a "$OUT"
echo "  - Unique line ratio: ≥${THRESH_UNIQUE}" | tee -a "$OUT"
echo "  - Max filler words: ≤${MAX_FILLERS}" | tee -a "$OUT"
echo "  - Max line repeat: ≤30%" | tee -a "$OUT"
echo "=======================================" | tee -a "$OUT"
echo "" | tee -a "$OUT"

# Hedeflenen dosya uzantıları (kaynak ve doküman)
FILES=()
while IFS= read -r -d '' file; do
  FILES+=("$file")
done < <(find "$ROOT" -type f \( \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o \
  -name '*.mjs' -o -name '*.cjs' -o -name '*.md' -o -name '*.json' -o \
  -name '*.sh' -o -name 'Dockerfile' -o -name '*.yml' -o -name '*.yaml' \
\) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
  -not -path "*/build/*" -not -path "*/coverage/*" -not -path "*/target/*" \
  -not -path "*/.next/*" -not -path "*/cypress/*" -print0)

echo "Files to analyze: ${#FILES[@]}" | tee -a "$OUT"
echo "" | tee -a "$OUT"

# Dolgu/filler kalıpları
FILLERS_REGEX='(LOREM|IPSUM|PLACEHOLDER|DUMMY|FILLER|PADDING|TODO|FIXME|TEMPLATE\s+ONLY|SAMPLE\s+ONLY|COPY\s+PASTE|deterministic|line\s+[0-9]+\s+[a-f0-9]+)'

check_file () {
  local f="$1"
  local fname=$(basename "$f")
  local total unique uniq_ratio fillers top_line_ratio
  
  # Satır sayısı
  total=$(wc -l < "$f" 2>/dev/null || echo "0")
  total=${total//[^0-9]/}  # Sadece rakamları al
  
  if [ -z "$total" ] || [ "$total" -eq 0 ]; then
    echo "[SKIP] $f (empty file)" | tee -a "$OUT"
    return 0
  fi

  # Benzersiz satır sayısı
  unique=$(sort -u "$f" 2>/dev/null | wc -l || echo "0")
  unique=${unique//[^0-9]/}  # Sadece rakamları al
  
  # Benzersiz oran hesapla
  if [ "$total" -gt 0 ]; then
    uniq_ratio=$(awk -v u="$unique" -v t="$total" 'BEGIN{ printf("%.2f", u/t) }')
  else
    uniq_ratio="1.00"
  fi
  
  # Filler/placeholder sayısı
  fillers=$(grep -Eio "$FILLERS_REGEX" "$f" 2>/dev/null | wc -l || echo "0")
  fillers=${fillers//[^0-9]/}  # Sadece rakamları al
  
  # En sık tekrarlanan satır oranı
  top_line_ratio=$(awk '
    length($0)>=20 {c[$0]++} 
    END {
      max=0; sum=0; 
      for(k in c) {
        sum+=c[k]; 
        if(c[k]>max) max=c[k]
      } 
      if(sum==0) print "0.00"; 
      else printf("%.2f", max/sum)
    }' "$f" 2>/dev/null || echo "0.00")
  
  local status="PASS"
  local reasons=()
  
  # Kalite kontrolleri
  # 1) Benzersiz satır oranı kontrolü
  if awk -v r="$uniq_ratio" -v t="$THRESH_UNIQUE" 'BEGIN{exit (r < t)}'; then
    : # Pass
  else
    status="FAIL"
    reasons+=("unique_ratio=${uniq_ratio}<${THRESH_UNIQUE}")
  fi
  
  # 2) Filler kelime kontrolü
  if [ "$fillers" -le "$MAX_FILLERS" ]; then
    : # Pass
  else
    status="FAIL"
    reasons+=("fillers=${fillers}>${MAX_FILLERS}")
  fi
  
  # 3) Tekrarlanan satır kontrolü
  if awk -v r="$top_line_ratio" 'BEGIN{exit (r > 0.30)}'; then
    : # Pass
  else
    status="FAIL"
    reasons+=("repeat_ratio=${top_line_ratio}>0.30")
  fi
  
  # Genesis-specific padding patterns
  if grep -q "line [0-9]* [a-f0-9]* deterministic" "$f" 2>/dev/null; then
    status="FAIL"
    reasons+=("genesis_padding_detected")
  fi
  
  # Sonuç yazdır
  if [ "$status" = "FAIL" ]; then
    echo "[❌ FAIL] $f" | tee -a "$OUT"
    echo "         Lines: $total | Unique: $unique ($uniq_ratio) | Fillers: $fillers | Repeat: $top_line_ratio" | tee -a "$OUT"
    echo "         Reasons: ${reasons[*]}" | tee -a "$OUT"
    ((FAIL_COUNT++))
    return 1
  else
    echo "[✅ PASS] $f" | tee -a "$OUT"
    echo "         Lines: $total | Unique: $unique ($uniq_ratio) | Fillers: $fillers | Repeat: $top_line_ratio" | tee -a "$OUT"
    ((PASS_COUNT++))
    return 0
  fi
}

echo "=======================================" | tee -a "$OUT"
echo "         FILE ANALYSIS RESULTS         " | tee -a "$OUT"
echo "=======================================" | tee -a "$OUT"

# Dosyaları analiz et
for f in "${FILES[@]}"; do
  ((TOTAL_COUNT++))
  check_file "$f" || true
done

echo "" | tee -a "$OUT"
echo "=======================================" | tee -a "$OUT"
echo "            SUMMARY REPORT             " | tee -a "$OUT"
echo "=======================================" | tee -a "$OUT"
echo "Total files analyzed: $TOTAL_COUNT" | tee -a "$OUT"
echo "✅ Passed: $PASS_COUNT" | tee -a "$OUT"
echo "❌ Failed: $FAIL_COUNT" | tee -a "$OUT"

if [ "$TOTAL_COUNT" -gt 0 ]; then
  PASS_RATE=$(awk -v p="$PASS_COUNT" -v t="$TOTAL_COUNT" 'BEGIN{ printf("%.1f", p*100/t) }')
  echo "Pass rate: ${PASS_RATE}%" | tee -a "$OUT"
else
  echo "Pass rate: N/A" | tee -a "$OUT"
fi

echo "=======================================" | tee -a "$OUT"

# Problem dosyaları listele
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "" | tee -a "$OUT"
  echo "⚠️  PROBLEMATIC FILES (Top Issues):" | tee -a "$OUT"
  echo "-----------------------------------" | tee -a "$OUT"
  grep "^\[❌ FAIL\]" "$OUT" | head -10 | while read line; do
    echo "$line" | tee -a "$OUT.problems"
  done
  echo "" | tee -a "$OUT"
  echo "💡 RECOMMENDATIONS:" | tee -a "$OUT"
  echo "  1. Remove padding/filler content" | tee -a "$OUT"
  echo "  2. Replace 'deterministic' comments with real code" | tee -a "$OUT"
  echo "  3. Implement actual functionality instead of placeholders" | tee -a "$OUT"
  echo "  4. Reduce code duplication" | tee -a "$OUT"
  echo "" | tee -a "$OUT"
fi

# Final durum
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "🎉 RESULT: ALL QUALITY GATES PASSED! ✅" | tee -a "$OUT"
  echo "=======================================" | tee -a "$OUT"
  exit 0
else
  echo "❌ RESULT: QUALITY GATES FAILED" | tee -a "$OUT"
  echo "   $FAIL_COUNT files need improvement" | tee -a "$OUT"
  echo "=======================================" | tee -a "$OUT"
  exit 1
fi