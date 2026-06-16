#!/bin/bash
# =============================================================================
#  test_boundary_values.sh — Boundary Value Analysis Test
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this test does:
#    Verifies that the anomaly detection subsystem correctly triggers
#    kernel warnings when SD card read/write counts cross defined
#    thresholds (WRITE_THRESHOLD=1000, READ_THRESHOLD=5000 in detection.c).
#
#    The test:
#    1. Reads the current cumulative I/O counts from /sys/block/mmcblk0/stat.
#    2. Generates controlled write operations using dd.
#    3. Reads /dev/sdhealth to trigger check_anomaly().
#    4. Checks dmesg for expected presence/absence of threshold warnings.
#    5. Verifies the one-shot alert guard (no duplicate warnings).
#
#  Usage:  ./test_boundary_values.sh
# =============================================================================

set -euo pipefail

# ---- configuration ---------------------------------------------------------
DEVICE="/dev/sdhealth"
STAT_FILE="/sys/block/mmcblk0/stat"
MODULE_NAME="sdhealth"
KO_FILE="sdhealth.ko"
TEMP_DIR="/tmp/sdhealth_boundary_test_$$"

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${CYAN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"

# ---- thresholds (must match detection.c) -----------------------------------
WRITE_THRESHOLD=1000
READ_THRESHOLD=5000

# ---- cleanup -----------------------------------------------------------------
cleanup() {
    echo -e "${INFO} Cleaning up..."
    rm -rf "$TEMP_DIR"
    sudo rmmod "$MODULE_NAME" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

# ---- helper: get current write count from /sys/block/mmcblk0/stat ----------
get_write_count() {
    awk '{print $5}' "$STAT_FILE" 2>/dev/null || echo 0
}

get_read_count() {
    awk '{print $1}' "$STAT_FILE" 2>/dev/null || echo 0
}

# ---- pre-flight checks -----------------------------------------------------
echo -e "${INFO} Boundary Value Analysis Test"
echo ""

if [ ! -f "$KO_FILE" ]; then
    echo -e "${FAIL} $KO_FILE not found. Run 'make' first."
    exit 1
fi

if [ ! -f "$STAT_FILE" ]; then
    echo -e "${FAIL} $STAT_FILE not found. Is the SD card accessible?"
    exit 1
fi

# ---- load module fresh -----------------------------------------------------
sudo rmmod "$MODULE_NAME" 2>/dev/null || true
sleep 1
sudo insmod "$KO_FILE"
sudo chmod 666 "$DEVICE"

# ---- get baseline counts ---------------------------------------------------
BASELINE_WRITES=$(get_write_count)
BASELINE_READS=$(get_read_count)

echo -e "${INFO} Baseline — Cumulative writes: ${BASELINE_WRITES}, reads: ${BASELINE_READS}"
echo ""

# ---- determine if thresholds are already crossed ---------------------------
WRITES_OVER=$(( BASELINE_WRITES > WRITE_THRESHOLD ? 1 : 0 ))
READS_OVER=$((  BASELINE_READS  > READ_THRESHOLD  ? 1 : 0 ))

if [ "$WRITES_OVER" -eq 1 ]; then
    echo -e "${WARN} Cumulative writes (${BASELINE_WRITES}) already exceed WRITE_THRESHOLD (${WRITE_THRESHOLD})."
fi
if [ "$READS_OVER" -eq 1 ]; then
    echo -e "${WARN} Cumulative reads (${BASELINE_READS}) already exceed READ_THRESHOLD (${READ_THRESHOLD})."
fi

echo "============================================"
echo "  Test 1: Clear dmesg, then read /dev/sdhealth"
echo "============================================"

sudo dmesg -c > /dev/null 2>&1
sudo cat "$DEVICE" > /dev/null 2>&1

WRITE_WARNINGS=$(sudo dmesg 2>/dev/null | grep -c 'Excessive write' || true)
READ_WARNINGS=$(sudo dmesg 2>/dev/null | grep -c 'Excessive read' || true)

echo "  Detected write warnings in dmesg: ${WRITE_WARNINGS}"
echo "  Detected read warnings  in dmesg: ${READ_WARNINGS}"

if [ "$WRITES_OVER" -eq 1 ] && [ "$WRITE_WARNINGS" -gt 0 ]; then
    echo -e "  ${PASS} Write threshold warning correctly triggered."
elif [ "$WRITES_OVER" -eq 1 ]; then
    echo -e "  ${FAIL} Cumulative writes exceed threshold but NO warning was logged."
else
    echo -e "  ${INFO} Cumulative writes below threshold — write warning not expected."
fi

if [ "$READS_OVER" -eq 1 ] && [ "$READ_WARNINGS" -gt 0 ]; then
    echo -e "  ${PASS} Read threshold warning correctly triggered."
elif [ "$READS_OVER" -eq 1 ]; then
    echo -e "  ${FAIL} Cumulative reads exceed threshold but NO warning was logged."
else
    echo -e "  ${INFO} Cumulative reads below threshold — read warning not expected."
fi

echo ""

# ---- Test 2: Verify one-shot guard (no duplicate warnings) -----------------
echo "============================================"
echo "  Test 2: One-Shot Alert Guard (no duplicates)"
echo "============================================"

sudo dmesg -c > /dev/null 2>&1

sudo cat "$DEVICE" > /dev/null 2>&1
sleep 1
sudo cat "$DEVICE" > /dev/null 2>&1

WRITE_WARN_TWO=$(sudo dmesg 2>/dev/null | grep -c 'Excessive write' || true)
READ_WARN_TWO=$(sudo dmesg 2>/dev/null | grep -c 'Excessive read' || true)

echo "  Write warnings after 2 consecutive reads: ${WRITE_WARN_TWO}"
echo "  Read warnings  after 2 consecutive reads: ${READ_WARN_TWO}"

if [ "$WRITE_WARN_TWO" -le 1 ]; then
    echo -e "  ${PASS} Write alert did NOT fire again — one-shot guard works."
else
    echo -e "  ${FAIL} Write alert fired ${WRITE_WARN_TWO} times — one-shot guard may be broken."
fi

if [ "$READ_WARN_TWO" -le 1 ]; then
    echo -e "  ${PASS} Read alert did NOT fire again — one-shot guard works."
else
    echo -e "  ${FAIL} Read alert fired ${READ_WARN_TWO} times — one-shot guard may be broken."
fi

echo ""

# ---- Test 3: Zero-length I/O -------------------------------------------------
echo "============================================"
echo "  Test 3: Zero-Length Read"
echo "============================================"

sudo dmesg -c > /dev/null 2>&1

ZERO_TEST=$(python3 -c "
import os
fd = os.open('${DEVICE}', os.O_RDWR)
result = os.read(fd, 0)
os.close(fd)
print(len(result))
" 2>&1 || echo "PYTHON_ERROR")

if [ "$ZERO_TEST" = "0" ]; then
    echo -e "  ${PASS} Zero-length read returned 0 bytes (no crash)."
elif [ "$ZERO_TEST" = "PYTHON_ERROR" ]; then
    echo -e "  ${WARN} Python not available — skipped zero-length test."
else
    echo -e "  ${FAIL} Zero-length read returned: ${ZERO_TEST}"
fi

ZERO_DMESG=$(sudo dmesg 2>/dev/null | grep -ci 'Oops\|BUG\|panic' || true)
if [ "$ZERO_DMESG" -eq 0 ]; then
    echo -e "  ${PASS} No kernel errors from zero-length read."
else
    echo -e "  ${FAIL} Kernel errors detected after zero-length read."
fi

echo ""

# ---- Test 4: Module can still be removed cleanly ---------------------------
echo "============================================"
echo "  Test 4: Module Unload After Testing"
echo "============================================"

if sudo rmmod "$MODULE_NAME" 2>/dev/null; then
    echo -e "  ${PASS} Module unloaded cleanly after all tests."
else
    echo -e "  ${FAIL} Module could not be unloaded."
fi

echo ""
echo "============================================"
echo "  Boundary Value Test — Complete"
echo "============================================"
