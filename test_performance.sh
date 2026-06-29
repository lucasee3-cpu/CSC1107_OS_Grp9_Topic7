#!/bin/bash
# =============================================================================
#  test_performance.sh — Module Performance Benchmark
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  Measures key performance metrics of the sdhealth kernel module:
#    1. insmod latency   — time to load the module
#    2. rmmod latency    — time to unload the module
#    3. read latency     — time to read stats from /dev/sdhealth
#    4. throughput       — sustained read operations per second
#
#  Usage:  ./test_performance.sh [iterations]
#          iterations = number of samples per metric (default: 50)
# =============================================================================

set -euo pipefail

ITERATIONS="${1:-50}"
DEVICE="/dev/sdhealth"
KO_FILE="sdhealth.ko"
MODULE_NAME="sdhealth"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}PASS${NC}"
INFO="${CYAN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"

# ---- cleanup -----------------------------------------------------------------
cleanup() {
    timeout 10 sudo rmmod "$MODULE_NAME" 2>/dev/null || true
    rm -f /tmp/sdhealth_perf_*.tmp
}
trap cleanup EXIT

# ---- pre-flight --------------------------------------------------------------
echo -e "${INFO} Performance Benchmark — ${ITERATIONS} samples per metric"
echo ""

if [ ! -f "$KO_FILE" ]; then
    echo -e "${RED}[FAIL]${NC} $KO_FILE not found. Run 'make' first."
    exit 1
fi

# ---- helper: compute statistics ---------------------------------------------
stats() {
    # Reads numbers from stdin, prints: min max avg median
    local file="$1"
    sort -n "$file" > "${file}.sorted"
    local count=$(wc -l < "$file")
    local min=$(head -1 "${file}.sorted")
    local max=$(tail -1 "${file}.sorted")
    local sum=$(paste -sd+ "$file" | bc 2>/dev/null || awk '{s+=$1}END{print s}')
    local avg=$(awk "BEGIN { printf \"%.3f\", $sum / $count }")
    local mid=$(( (count + 1) / 2 ))
    local median=$(sed -n "${mid}p" "${file}.sorted")
    echo "$min $max $avg $median"
}

# ---- 1: insmod latency ------------------------------------------------------
echo "============================================"
echo "  Test 1: insmod Latency"
echo "============================================"

sudo rmmod "$MODULE_NAME" 2>/dev/null || true
INSMOD_FILE="/tmp/sdhealth_perf_insmod.tmp"
> "$INSMOD_FILE"

for (( i=1; i<=ITERATIONS; i++ )); do
    sudo rmmod "$MODULE_NAME" 2>/dev/null || true
    sleep 0.05
    START=$(date +%s%N)
    sudo insmod "$KO_FILE" 2>/dev/null
    END=$(date +%s%N)
    ELAPSED_MS=$(awk "BEGIN { printf \"%.3f\", ($END - $START) / 1000000 }")
    echo "$ELAPSED_MS" >> "$INSMOD_FILE"
done

read INS_MIN INS_MAX INS_AVG INS_MED <<< $(stats "$INSMOD_FILE")
echo "  Samples : $ITERATIONS"
echo "  Min     : ${INS_MIN} ms"
echo "  Max     : ${INS_MAX} ms"
echo "  Average : ${INS_AVG} ms"
echo "  Median  : ${INS_MED} ms"
echo ""

# ---- 2: rmmod latency -------------------------------------------------------
echo "============================================"
echo "  Test 2: rmmod Latency"
echo "============================================"

RMMOD_FILE="/tmp/sdhealth_perf_rmmod.tmp"
> "$RMMOD_FILE"

for (( i=1; i<=ITERATIONS; i++ )); do
    sudo insmod "$KO_FILE" 2>/dev/null
    sleep 0.05
    START=$(date +%s%N)
    sudo rmmod "$MODULE_NAME" 2>/dev/null
    END=$(date +%s%N)
    ELAPSED_MS=$(awk "BEGIN { printf \"%.3f\", ($END - $START) / 1000000 }")
    echo "$ELAPSED_MS" >> "$RMMOD_FILE"
done

read RMM_MIN RMM_MAX RMM_AVG RMM_MED <<< $(stats "$RMMOD_FILE")
echo "  Samples : $ITERATIONS"
echo "  Min     : ${RMM_MIN} ms"
echo "  Max     : ${RMM_MAX} ms"
echo "  Average : ${RMM_AVG} ms"
echo "  Median  : ${RMM_MED} ms"
echo ""

# ---- 3: read latency --------------------------------------------------------
echo "============================================"
echo "  Test 3: Read Latency (/dev/sdhealth)"
echo "============================================"

sudo insmod "$KO_FILE" 2>/dev/null
sudo chmod 666 "$DEVICE"
READ_FILE="/tmp/sdhealth_perf_read.tmp"
> "$READ_FILE"

for (( i=1; i<=ITERATIONS; i++ )); do
    START=$(date +%s%N)
    timeout 5 cat "$DEVICE" > /dev/null 2>&1
    END=$(date +%s%N)
    ELAPSED_MS=$(awk "BEGIN { printf \"%.3f\", ($END - $START) / 1000000 }")
    echo "$ELAPSED_MS" >> "$READ_FILE"
done

read RD_MIN RD_MAX RD_AVG RD_MED <<< $(stats "$READ_FILE")
echo "  Samples : $ITERATIONS"
echo "  Min     : ${RD_MIN} ms"
echo "  Max     : ${RD_MAX} ms"
echo "  Average : ${RD_AVG} ms"
echo "  Median  : ${RD_MED} ms"
echo ""

# ---- 4: sustained throughput ------------------------------------------------
echo "============================================"
echo "  Test 4: Read Throughput (ops/sec)"
echo "============================================"

DURATION=10
COUNT=0
DEADLINE=$(( $(date +%s) + DURATION ))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    timeout 2 cat "$DEVICE" > /dev/null 2>&1 && COUNT=$((COUNT + 1)) || true
done

THROUGHPUT=$(awk "BEGIN { printf \"%.1f\", $COUNT / $DURATION }")
echo "  Duration   : ${DURATION}s"
echo "  Operations : $COUNT"
echo "  Throughput : ${THROUGHPUT} reads/sec"
echo ""

# ---- summary ----------------------------------------------------------------
sudo rmmod "$MODULE_NAME" 2>/dev/null || true

echo "============================================"
echo "  Performance Summary"
echo "============================================"
echo ""
echo "  Metric              |  Min       |  Max       |  Average   |  Median"
echo "  --------------------|------------|------------|------------|-----------"
printf "  insmod latency      | %8s ms | %8s ms | %8s ms | %8s ms\n" "$INS_MIN" "$INS_MAX" "$INS_AVG" "$INS_MED"
printf "  rmmod latency       | %8s ms | %8s ms | %8s ms | %8s ms\n" "$RMM_MIN" "$RMM_MAX" "$RMM_AVG" "$RMM_MED"
printf "  read latency        | %8s ms | %8s ms | %8s ms | %8s ms\n" "$RD_MIN" "$RD_MAX" "$RD_AVG" "$RD_MED"
echo ""
echo "  Sustained read throughput: ${THROUGHPUT} reads/sec"
echo ""
echo "============================================"
