#!/usr/bin/env bash
set -euo pipefail

# ---------- Defaults ----------
INPUT_FILE=""
OUTPUT_FILE=""
CHUNK_LINES="${CHUNK_LINES:-5000000}"  # ~5M lines per chunk
USE_MAWK="${USE_MAWK:-1}"

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-file)
      INPUT_FILE="$2"
      shift 2
      ;;
    --output-file)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --chunk-lines)
      CHUNK_LINES="$2"
      shift 2
      ;;
    --no-mawk)
      USE_MAWK=0
      shift
      ;;
    -h|--help)
      echo "Usage: $0 --input-file FILE --output-file FILE [--chunk-lines N] [--no-mawk]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$INPUT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "ERROR: --input-file and --output-file are required"
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: input file not found: $INPUT_FILE"
  exit 1
fi

OUT_DIR="$(dirname "$OUTPUT_FILE")/extract-$(date +%s)"
mkdir -p "$OUT_DIR"/{chunks,uniqs}
LOG="$OUT_DIR/run.log"

echo "[$(date '+%F %T')] Start - INPUT=$INPUT_FILE OUTPUT=$OUTPUT_FILE CHUNK_LINES=$CHUNK_LINES" | tee -a "$LOG"

# ---------- Select awk variant ----------
AWK_BIN="awk"
if [[ "$USE_MAWK" == "1" ]] && command -v mawk >/dev/null 2>&1; then
  AWK_BIN="mawk"
fi
echo "[$(date '+%F %T')] Using: $AWK_BIN" | tee -a "$LOG"

# ---------- Split input ----------
echo "[$(date '+%F %T')] Splitting into chunks of $CHUNK_LINES lines..." | tee -a "$LOG"
split -l "$CHUNK_LINES" --numeric-suffixes=1 --suffix-length=5 --additional-suffix=".part" \
  "$INPUT_FILE" "$OUT_DIR/chunks/chunk_"

# ---------- Extraction function ----------
extract_chunk() {
  local chunk="$1"
  local base
  base="$(basename "$chunk" .part)"
  local out="$OUT_DIR/uniqs/${base}.uniqs"

  $AWK_BIN '
    {
      hasD = match($0, /devip=([^ ]+)/, d)
      hasF = match($0, /fw="([^"]+)"/, f)
      if (hasD && hasF) {
        key = d[1] " " f[1]
        if (!seen[key]++) {
          print d[1], f[1]
        }
      }
    }
  ' "$chunk" > "$out"

  echo "[$(date '+%F %T')] Done: $(basename "$chunk") -> $(wc -l < "$out") uniques" | tee -a "$LOG"
}

export -f extract_chunk
export OUT_DIR AWK_BIN LOG

# ---------- Process chunks ----------
for c in "$OUT_DIR"/chunks/chunk_*.part; do
  extract_chunk "$c"
done

# ---------- Merge ----------
echo "[$(date '+%F %T')] Merging uniques..." | tee -a "$LOG"
cat "$OUT_DIR"/uniqs/*.uniqs | LC_ALL=C sort -u > "$OUTPUT_FILE"
echo "[$(date '+%F %T')] Final output: $OUTPUT_FILE (lines: $(wc -l < "$OUTPUT_FILE"))" | tee -a "$LOG"
