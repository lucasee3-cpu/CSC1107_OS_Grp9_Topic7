#!/bin/bash
# =============================================================================
#  test_race_conditions.sh — Concurrency / Race Condition Test
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this test does:
#    Spawns multiple parallel reader/writer processes that hammer
#    /dev/sdhealth simultaneously.  Each reader writes its output to a
#    separate log file.  After the test, adjacent log files are compared
#    (diff) — any divergence may indicate a torn/inconsistent read caused
#    by concurrent access to the module's global static variables without
#    locking.
#
#    Also monitors dmesg throughout for kernel Oops, BUG, WARN_ON, or
#    panic messages that would indicate a kernel-level concurrency bug.
#
#  Usage:  ./test_race_conditions.sh [readers] [duration_seconds]
#          readers          = number of parallel reader processes (default: 16)
#          duration_seconds = how long to run the test (default: 30)
# =============================================================================

set -euo pipefail

# ---- configuration ---------------------------------------------------------
READERS="${1:-16}"              # number of parallel reader processes
DURATION="${2:-30}"             # test duration in seconds
DEVICE="/dev/sdhealth"
LOG_DIR="/tmp/sdhealth_race_test_$$"
MODULE_NAME="sdhealth"
KO_FILE="sdhealth.ko"

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${CYAN}[INFO]${NC}"

# ---- cleanup trap ----------------------------------------------------------
cleanup() {
    echo -e "${INFO} Cleaning up test processes..."
    pkill -f "sdhealth_race_reader" 2>/dev/null || true
    pkill -f "sdhealth_race_writer" 2>/dev/null || true
    timeout 10 sudo rmmod "$MODULE_NAME" 2>/dev/null || true
    echo -e "${INFO} Test artifacts preserved in: ${LOG_DIR}"
}
trap cleanup EXIT

# ---- helper: single reader process -----------------------------------------
reader_worker() {
    local id="$1"
    local logfile="$2"
    local deadline="$3"
    local fd
    local buf
    local n

    exec {fd}<>"$DEVICE" 2>/dev/null || {
        echo "[reader $id] FAILED to open $DEVICE" >> "$logfile"
        return 1
    }

    while [ "$(date +%s)" -lt "$deadline" ]; do
        echo "REQUEST_STATS" >&${fd} 2>/dev/null || true
        IFS= read -r -t 1 -u ${fd} buf 2>/dev/null && {
            echo "[reader $id] $(date +%T.%N) $buf" >> "$logfile"
        } || true
    done

    exec {fd}>&- 2>/dev/null || true
}
export -f reader_worker

# ---- helper: single writer process -----------------------------------------
writer_worker() {
    local id="$1"
    local logfile="$2"
    local deadline="$3"
    local fd

    exec {fd}<>"$DEVICE" 2>/dev/null || {
        echo "[writer $id] FAILED to open $DEVICE" >> "$logfile"
        return 1
    }

    while [ "$(date +%s)" -lt "$deadline" ]; do
        echo "REQUEST_STATS" >&${fd} 2>/dev/null || true
        sleep 0.1
    done

    exec {fd}>&- 2>/dev/null || true
}
export -f writer_worker

# ---- pre-flight checks -----------------------------------------------------
echo -e "${INFO} Race Condition Test — ${READERS} readers, ${DURATION}s duration"

if [ ! -f "$KO_FILE" ]; then
    echo -e "${FAIL} $KO_FILE not found. Run 'make' first."
    exit 1
fi

if lsmod | grep -q "^${MODULE_NAME}"; then
    timeout 10 sudo rmmod "$MODULE_NAME" 2>/dev/null || true
    sleep 1
fi

timeout 10 sudo insmod "$KO_FILE"
sudo chmod 666 "$DEVICE"

if [ ! -e "$DEVICE" ]; then
    echo -e "${FAIL} $DEVICE not found after insmod."
    exit 1
fi

echo -e "${INFO} Device ready: $(ls -l $DEVICE)"

# ---- setup log directory ---------------------------------------------------
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
DEADLINE=$(( $(date +%s) + DURATION ))

# ---- clear dmesg ring buffer before test -----------------------------------
sudo dmesg -c > /dev/null 2>&1 || true

# ---- launch reader processes -----------------------------------------------
echo -e "${INFO} Launching ${READERS} parallel readers..."
READER_PIDS=()
for (( i=0; i<READERS; i++ )); do
    reader_worker "$i" "${LOG_DIR}/reader_${i}.log" "$DEADLINE" &
    READER_PIDS+=($!)
done

# ---- launch a single writer process ----------------------------------------
echo -e "${INFO} Launching 1 writer process (interleaved writes)..."
writer_worker "W" "${LOG_DIR}/writer.log" "$DEADLINE" &
WRITER_PID=$!

# ---- wait for test duration ------------------------------------------------
echo -e "${INFO} Test running for ${DURATION} seconds..."
echo "       Press Ctrl+C to stop early."
sleep "$DURATION"
echo -e "${INFO} Time's up — waiting for children to exit..."

# ---- wait for all processes ------------------------------------------------
# Kill any remaining reader/writer processes first
pkill -f sdhealth_race_reader 2>/dev/null || true
pkill -f sdhealth_race_writer 2>/dev/null || true
sleep 1

# Wait with timeout — processes stuck in D-state (kernel lock) cannot be killed,
# so we give each one at most 5 seconds before moving on
for pid in "${READER_PIDS[@]}"; do
    timeout 5 wait "$pid" 2>/dev/null || true
done
timeout 5 wait "$WRITER_PID" 2>/dev/null || true

echo -e "${INFO} All reader/writer processes have been collected."

# ---- check dmesg for kernel errors -----------------------------------------
echo ""
echo "============================================"
echo "  Race Condition Test — Results"
echo "============================================"
echo "  Readers spawned  : ${READERS}"
echo "  Duration         : ${DURATION}s"
echo ""

DMESG_OUT=$(sudo dmesg 2>/dev/null || true)

OOPS_COUNT=$(echo "$DMESG_OUT" | grep -ci 'Oops\|BUG\|WARN_ON\|panic\|Unable to handle' || true)
if [ "$OOPS_COUNT" -gt 0 ]; then
    echo -e "${FAIL} KERNEL ERRORS DETECTED (${OOPS_COUNT} occurrences):"
    echo "$DMESG_OUT" | grep -i 'Oops\|BUG\|WARN_ON\|panic\|Unable to handle' | head -10
    echo ""
else
    echo -e "${PASS} No kernel Oops / BUG / panic detected."
fi

# ---- analyse reader logs ---------------------------------------------------
echo ""
echo "  Reader log analysis:"
TOTAL_LINES=0

for (( i=0; i<READERS; i++ )); do
    LOGFILE="${LOG_DIR}/reader_${i}.log"
    if [ -f "$LOGFILE" ]; then
        LINES=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)
        TOTAL_LINES=$((TOTAL_LINES + LINES))
    fi
done

echo "  Total log lines collected: ${TOTAL_LINES}"

# ---- diff adjacent reader pairs for inconsistency --------------------------
MISMATCHES=0
for (( i=0; i<READERS-1; i++ )); do
    F1="${LOG_DIR}/reader_${i}.log"
    F2="${LOG_DIR}/reader_$((i+1)).log"

    if [ -f "$F1" ] && [ -f "$F2" ]; then
        STATS1=$(grep -oP 'Reads:.*' "$F1" 2>/dev/null | sort -u || true)
        STATS2=$(grep -oP 'Reads:.*' "$F2" 2>/dev/null | sort -u || true)

        if [ "$STATS1" != "$STATS2" ] && [ -n "$STATS1" ] && [ -n "$STATS2" ]; then
            MISMATCHES=$((MISMATCHES + 1))
        fi
    fi
done

if [ "$MISMATCHES" -gt 0 ]; then
    echo -e "${FAIL} ${MISMATCHES} reader pair(s) show inconsistent output — possible race condition."
    echo "  Compare files in: ${LOG_DIR}/reader_*.log"
else
    echo -e "${PASS} All reader pairs show consistent statistics."
fi

echo ""
echo "  Logs preserved in: ${LOG_DIR}"
echo "============================================"
echo ""
echo -e "${INFO} Run 'sudo dmesg' to review kernel output."
echo -e "${INFO} Run './cleanup.sh' to remove the module."
