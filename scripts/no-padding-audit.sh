#!/usr/bin/env bash
# no-padding-audit v3 – newline/pipefail-safe, exclude destekli
set -euo pipefail

ROOT="${1:-.}"
OUT="${2:-logs/no_padding_audit_$(date +%Y%m%d_%H%M%S).log}"

THRESH_UNIQUE=0.70   # benzersiz satır oranı eşiği
MAX_FILLERS=3        # filler ifadelere izin verilen üst sınır
FAIL=0

# Dolgu/filler kalıpları
FILLERS_REGEX='(LOREM|IPSUM|PLACEHOLDER|DUMMY|FILLER|PADDING|TO[[:space:]]*DO|TODO|FIXME|TEMPLATE[[:space:]]+ONLY|SAMPLE[[:space:]]+ONLY|COPY[[:space:]]+PASTE)'

# Exclude listesi (.no-padding-exclude dosyası varsa klasörleri dışla)
EX_PRUNE_ARGS=()
if [[ -f ".no-padding-exclude" ]]; then
  while IFS= read -r line; do
    l="${line%%#*}"; l="$(echo "$l" | xargs || true)"
    [[ -z "${l}" ]] && continue
    EX_PRUNE_ARGS+=( -path "$ROOT/${l%/}/*" -prune -o )
  done < .no-padding-exclude
fi

# Her halükârda bazı klasörleri dışlayalım
EX_PRUNE_ARGS+=(
  -path "$ROOT/node_modules/*" -prune -o
  -path "$ROOT/.git/*" -prune -o
)

echo "== NO-PADDING AUDIT ==" > "$OUT"
{
  echo "root: $ROOT"
  echo "time: $(date -Is)"
  echo
} >> "$OUT"

# Hedef dosya tipleri
readarray -t FILES < <(
  # shellcheck disable=SC2016
  find "$ROOT" \
    "${EX_PRUNE_ARGS[@]}" \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o \
               -name '*.mjs' -o -name '*.cjs' -o -name '*.md' -o -name '*.json' -o \
               -name '*.sh' -o -name 'Dockerfile' -o -name '*.yml' -o -name '*.yaml' \) \
    -print
)

sanitize_int () {
  # sadece rakamları bırak
  local v="${1:-0}"
  v="${v//[!0-9]/}"
  [[ -z "$v" ]] && v=0
  printf "%d" "$v"
}

check_file () {
  local f="$1"

  # Toplam ve benzersiz satır: newline güvenli
  local total unique uniq_ratio
  total=$(wc -l < "$f" || echo 0); total=$(sanitize_int "$total")
  [[ "$total" -eq 0 ]] && return 0

  # LC_ALL=C ile deterministik sort
  unique=$(LC_ALL=C sort -u "$f" | wc -l || echo 0); unique=$(sanitize_int "$unique")
  uniq_ratio=$(awk -v u="$unique" -v t="$total" 'BEGIN{ if(t==0) print "1.00"; else printf("%.4f", u/t) }')

  # Filler sayısı: mapfile ile **satır say** (grep -c başarısız olduğunda bile 0 ver)
  local fillers
  mapfile -t _matches < <(grep -Eio "$FILLERS_REGEX" "$f" || true)
  fillers=${#_matches[@]}
  fillers=$(sanitize_int "$fillers")

  # En sık satır oranı (>=20 char) – tekrar sezgisi
  local top_line_ratio
  top_line_ratio=$(awk 'length($0)>=20{c[$0]++} END{m=0; s=0; for(k in c){s+=c[k]; if(c[k]>m)m=c[k]} if(s==0){print "0.00"} else {printf("%.4f", m/s)}}' "$f")

  local bad=0 reasons=()

  # 1) Benzersiz satır oranı
  awk -v r="$uniq_ratio" -v th="$THRESH_UNIQUE" 'BEGIN{ exit (r < th) }' || { bad=1; reasons+=("low-unique-ratio"); }

  # 2) Filler yoğunluğu (tam sayı, newline-safe)
  if (( fillers > MAX_FILLERS )); then bad=1; reasons+=("fillers>${MAX_FILLERS}"); fi

  # 3) Aşırı tekrar (en sık satır oranı)
  awk -v r="$top_line_ratio" 'BEGIN{ exit (r > 0.30) }' || { bad=1; reasons+=("top-line-repeat>0.30"); }

  if (( bad == 1 )); then
    printf "[FAIL] %s  total=%d unique=%d uniq_ratio=%s fillers=%d top_line_ratio=%s reasons=%s\n" \
      "$f" "$total" "$unique" "$uniq_ratio" "$fillers" "$top_line_ratio" "${reasons[*]}" >> "$OUT"
    return 1
  else
    printf "[OK]   %s  total=%d unique=%d uniq_ratio=%s fillers=%d top_line_ratio=%s\n" \
      "$f" "$total" "$unique" "$uniq_ratio" "$fillers" "$top_line_ratio" >> "$OUT"
    return 0
  fi
}

for f in "${FILES[@]}"; do
  check_file "$f" || FAIL=1
done

echo >> "$OUT"
if (( FAIL == 1 )); then
  echo "RESULT: FAIL" >> "$OUT"
  echo "Detaylı rapor: $OUT"
  exit 2
else
  echo "RESULT: OK" >> "$OUT"
  echo "Detaylı rapor: $OUT"
  exit 0
fi