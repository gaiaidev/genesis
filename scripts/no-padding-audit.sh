#!/usr/bin/env bash
# No-Padding Audit: içerik kalitesi kapısı
set -euo pipefail

ROOT="${1:-.}"
OUT="${2:-logs/no_padding_audit_$(date +%Y%m%d_%H%M%S).log}"
THRESH_UNIQUE=0.70   # benzersiz satır oranı eşiği
MAX_FILLERS=3        # filler ifadelere izin verilen üst sınır
FAIL=0

echo "== NO-PADDING AUDIT ==" > "$OUT"
echo "root: $ROOT" >> "$OUT"
echo "time: $(date -Is)" >> "$OUT"
echo >> "$OUT"

# Hedeflenen dosya uzantıları (kaynak ve doküman)
mapfile -t FILES < <(find "$ROOT" -type f \( \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o \
  -name '*.mjs' -o -name '*.cjs' -o -name '*.md' -o -name '*.json' -o \
  -name '*.sh' -o -name 'Dockerfile' -o -name '*.yml' -o -name '*.yaml' \
\) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" | head -100)

# Dolgu/filler kalıpları
FILLERS_REGEX='(LOREM|IPSUM|PLACEHOLDER|DUMMY|FILLER|PADDING|TO\s*DO|TODO|FIXME|TEMPLATE\s+ONLY|SAMPLE\s+ONLY|COPY\s+PASTE)'

check_file () {
  local f="$1"
  local total unique uniq_ratio fillers
  total=$(wc -l < "$f" | tr -d ' ')
  [[ "$total" -eq 0 ]] && return 0

  # benzersiz satır sayısı
  unique=$(sort -u "$f" | wc -l | tr -d ' ')
  # ondalık oran (bc yoksa awk)
  uniq_ratio=$(awk -v u="$unique" -v t="$total" 'BEGIN{ if(t==0) print 1; else printf("%.4f", u/t) }')

  # filler/placeholder sayısı (büyük/küçük harf duyarsız)
  fillers=$(grep -Eio "$FILLERS_REGEX" "$f" 2>/dev/null | wc -l || echo "0")
  fillers=$(echo "$fillers" | tr -d ' ')

  # aşırı tekrar basit sezgisi: 20+ karakterlik en sık satırın oranı
  top_line_ratio=$(awk 'length($0)>=20{c[$0]++} END{m=0; s=0; for(k in c){s+=c[k]; if(c[k]>m)m=c[k]} if(s==0){print "0.00"} else {printf("%.4f", m/s)}}' "$f")

  local bad=0
  local reasons=()

  # Eşik kontrolleri
  # 1) Benzersiz satır oranı
  awk -v r="$uniq_ratio" -v th="$THRESH_UNIQUE" 'BEGIN{ if (r < th) exit 1; else exit 0 }' || { bad=1; reasons+=("low-unique-ratio=$uniq_ratio"); }

  # 2) Filler yoğunluğu
  if [ "$fillers" -gt "$MAX_FILLERS" ]; then bad=1; reasons+=("fillers=$fillers>${MAX_FILLERS}"); fi

  # 3) En sık satır oranı (aşırı tekrar)
  awk -v r="$top_line_ratio" 'BEGIN{ if (r > 0.30) exit 1; else exit 0 }' || { bad=1; reasons+=("top-line-repeat=$top_line_ratio>0.30"); }

  if [[ $bad -eq 1 ]]; then
    echo "[FAIL] $f  total=$total unique=$unique uniq_ratio=$uniq_ratio fillers=$fillers top_line_ratio=$top_line_ratio reasons=${reasons[*]}" >> "$OUT"
    return 1
  else
    echo "[OK]   $f  total=$total unique=$unique uniq_ratio=$uniq_ratio fillers=$fillers top_line_ratio=$top_line_ratio" >> "$OUT"
    return 0
  fi
}

echo "== FILE ANALYSIS ==" >> "$OUT"
echo "Total files to check: ${#FILES[@]}" >> "$OUT"
echo >> "$OUT"

for f in "${FILES[@]}"; do
  if ! check_file "$f"; then
    FAIL=1
  fi
done

echo >> "$OUT"
if [[ $FAIL -eq 1 ]]; then
  echo "RESULT: FAIL - Quality gates not passed" >> "$OUT"
  echo "❌ No-Padding Audit: FAILED"
  echo "Detaylı rapor: $OUT"
  exit 2
else
  echo "RESULT: OK - All quality gates passed" >> "$OUT"
  echo "✅ No-Padding Audit: PASSED"
  echo "Detaylı rapor: $OUT"
  exit 0
fi
