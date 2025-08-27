#!/usr/bin/env bash
# Extract unique devip-fw pairs from large log files
# Compatible with both gawk and mawk
set -euo pipefail

# ---------- Defaults ----------
INPUT_FILE=""
OUTPUT_FILE=""
TOP_DEVIP_FILE=""                 # Optional: path for frequency table of devip
CHUNK_LINES="${CHUNK_LINES:-5000000}"  # ~5M lines per chunk
USE_MAWK="${USE_MAWK:-1}"

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-file)
      INPUT_FILE="$2"; shift 2 ;;
    --output-file)
      OUTPUT_FILE="$2"; shift 2 ;;
    --top-devip)
      TOP_DEVIP_FILE="$2"; shift 2 ;;
    --chunk-lines)
      CHUNK_LINES="$2"; shift 2 ;;
    --no-mawk)
      USE_MAWK=0; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  extract-devip-fw.sh --input-file FILE --output-file FILE [--top-devip FILE] [--chunk-lines N] [--no-mawk]

Description:
  - Extract unique pairs "devip fw" from a huge log file, chunk-by-chunk, and write to --output-file.
  - Optionally compute a frequency table of devip (how many lines per devip) to --top-devip.

Options:
  --input-file FILE     Input log file to process (required)
  --output-file FILE    Output file for unique "devip fw" pairs (required)
  --top-devip FILE      Also produce "count devip" frequency table (optional)
  --chunk-lines N       Lines per chunk (default: 5,000,000)  (env: CHUNK_LINES)
  --no-mawk             Force classic awk even if mawk is available
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$INPUT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "ERROR: --input-file and --output-file are required" >&2
  exit 1
fi
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: input file not found: $INPUT_FILE" >&2
  exit 1
fi

TS="$(date +%s)"
BASE_OUT_DIR="$(dirname "$OUTPUT_FILE")/extract-$TS"
mkdir -p "$BASE_OUT_DIR"/{chunks,uniqs}
[[ -n "$TOP_DEVIP_FILE" ]] && mkdir -p "$BASE_OUT_DIR"/top
LOG="$BASE_OUT_DIR/run.log"

echo "[$(date '+%F %T')] Start - INPUT=$INPUT_FILE OUTPUT=$OUTPUT_FILE CHUNK_LINES=$CHUNK_LINES" | tee -a "$LOG"
[[ -n "$TOP_DEVIP_FILE" ]] && echo "[$(date '+%F %T')] Also computing TOP devip -> $TOP_DEVIP_FILE" | tee -a "$LOG"

# ---------- Select awk variant ----------
AWK_BIN="awk"
if [[ "$USE_MAWK" == "1" ]] && command -v mawk >/dev/null 2>&1; then
  AWK_BIN="mawk"
fi
echo "[$(date '+%F %T')] Using: $AWK_BIN" | tee -a "$LOG"

# ---------- Split input into line-based chunks ----------
echo "[$(date '+%F %T')] Splitting into chunks of $CHUNK_LINES lines..." | tee -a "$LOG"
split -l "$CHUNK_LINES" --numeric-suffixes=1 --suffix-length=5 --additional-suffix=".part" \
  "$INPUT_FILE" "$BASE_OUT_DIR/chunks/chunk_"

# ---------- Functions ----------
extract_chunk_uniqs() {
  local chunk="$1"
  local out="$2"

  # Emit unique pairs "devip fw" within this chunk
  "$AWK_BIN" '
    {
      # Extract devip
      devip = ""
      if (match($0, /devip=[^ ]+/)) {
        devip = substr($0, RSTART+6, RLENGTH-6)
      }
      
      # Extract fw
      fw = ""
      if (match($0, /fw="[^"]+"/)) {
        fw = substr($0, RSTART+4, RLENGTH-5)
      }
      
      if (devip != "" && fw != "") {
        key = devip " " fw
        if (!seen[key]++) {
          print devip, fw
        }
      }
    }
  ' "$chunk" > "$out"
}

extract_chunk_top() {
  local chunk="$1"
  local out="$2"

  # Count devip frequency within this chunk; emit "count devip"
  "$AWK_BIN" '
    {
      if (match($0, /devip=[^ ]+/)) {
        devip = substr($0, RSTART+6, RLENGTH-6)
        cnt[devip]++
      }
    }
    END {
      for (k in cnt) printf "%d %s\n", cnt[k], k
    }
  ' "$chunk" | LC_ALL=C sort -k2,2 > "$out"
}

# ---------- Export for subshells if needed ----------
export AWK_BIN LOG BASE_OUT_DIR
export -f extract_chunk_uniqs extract_chunk_top

# ---------- Process chunks ----------
echo "[$(date '+%F %T')] Processing chunks..." | tee -a "$LOG"
for c in "$BASE_OUT_DIR"/chunks/chunk_*.part; do
  base="$(basename "$c" .part)"
  uniq_out="$BASE_OUT_DIR/uniqs/${base}.uniqs"
  extract_chunk_uniqs "$c" "$uniq_out"
  echo "[$(date '+%F %T')] uniques: $base -> $(wc -l < "$uniq_out") lines" | tee -a "$LOG"

  if [[ -n "$TOP_DEVIP_FILE" ]]; then
    top_out="$BASE_OUT_DIR/top/${base}.top"
    extract_chunk_top "$c" "$top_out"
    echo "[$(date '+%F %T')] top:    $base -> $(wc -l < "$top_out") devip(s)" | tee -a "$LOG"
  fi
done

# ---------- Merge uniques ----------
echo "[$(date '+%F %T')] Merging uniques..." | tee -a "$LOG"
cat "$BASE_OUT_DIR"/uniqs/*.uniqs | LC_ALL=C sort -u > "$OUTPUT_FILE"
echo "[$(date '+%F %T')] Final uniques: $OUTPUT_FILE (lines: $(wc -l < "$OUTPUT_FILE"))" | tee -a "$LOG"

# ---------- Merge TOP devip (optional) ----------
if [[ -n "$TOP_DEVIP_FILE" ]]; then
  echo "[$(date '+%F %T')] Merging TOP devip..." | tee -a "$LOG"

  # Merge sorted-by-devip per-chunk tallies by summing counts
  # Inputs lines: "count devip" (sorted by devip)
  cat "$BASE_OUT_DIR"/top/*.top \
    | LC_ALL=C sort -k2,2 \
    | "$AWK_BIN" '
        {
          # $1 = count, $2 = devip
          if (devip == $2) {
            total += $1
          } else {
            if (devip != "") printf "%d %s\n", total, devip
            devip = $2; total = $1
          }
        }
        END {
          if (devip != "") printf "%d %s\n", total, devip
        }
      ' \
    | LC_ALL=C sort -nr -k1,1 > "$TOP_DEVIP_FILE"

  echo "[$(date '+%F %T')] Final TOP devip: $TOP_DEVIP_FILE (lines: $(wc -l < "$TOP_DEVIP_FILE"))" | tee -a "$LOG"
fi

echo "[$(date '+%F %T')] Done. Temp dir: $BASE_OUT_DIR" | tee -a "$LOG"
echo "You may remove $BASE_OUT_DIR/chunks and $BASE_OUT_DIR/uniqs (and /top) when you’re satisfied." | tee -a "$LOG"
