#!/bin/bash
# =============================================================================
#  test_memory_leak.sh — Kernel Memory Leak Detection Test
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this test does:
#    Loads the sdhealth kernel module, waits briefly, then unloads it —
#    repeated N times.  Before and after the cycling, the script captures
#    /proc/meminfo to detect any monotonic decrease in free kernel memory,
#    which would indicate a memory leak in the module's init/exit paths.
#
#  Usage:  ./test_memory_leak.sh [cycles]
#          cycles = number of load/unload iterations (default: 100)
# =============================================================================

set -euo pipefail

# ---- configuration ---------------------------------------------------------
CYCLES="${1:-100}"               # default 100 load/unload pairs
WAIT_SEC=2                       # seconds to keep module loaded each cycle
MODULE_NAME="sdhealth"
KO_FILE="sdhealth.ko"

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${CYAN}[INFO]${NC}"

# ---- pre-flight checks -----------------------------------------------------
echo -e "${INFO} Memory Leak Test — ${CYCLES} load/unload cycles"
echo -e "${INFO} Checking prerequisites..."

if [ ! -f "$KO_FILE" ]; then
    echo -e "${FAIL} $KO_FILE not found. Run 'make' first."
    exit 1
fi

if ! lsmod | grep -q "^${MODULE_NAME}" 2>/dev/null; then
    :  # module not loaded — expected
else
    echo -e "${INFO} Module already loaded — removing first."
    sudo rmmod "$MODULE_NAME"
fi

# ---- capture baseline memory -----------------------------------------------
echo -e "${INFO} Capturing baseline memory..."
MEM_BEFORE=$(cat /proc/meminfo | grep -E '^MemFree|^MemAvailable' | tr '\n' ' ')
echo -e "       ${MEM_BEFORE}"

# ---- load/unload cycling ---------------------------------------------------
echo -e "${INFO} Starting ${CYCLES} load/unload cycles..."
PASS_COUNT=0
FAIL_COUNT=0

for (( i=1; i<=CYCLES; i++ )); do
    # LOAD
    if sudo insmod "$KO_FILE" 2>/dev/null; then
        sleep "$WAIT_SEC"
    else
        echo -e "${FAIL} Cycle $i: insmod failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sudo rmmod "$MODULE_NAME" 2>/dev/null || true
        continue
    fi

    # UNLOAD
    if sudo rmmod "$MODULE_NAME" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${FAIL} Cycle $i: rmmod failed (module stuck in use?)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sudo rmmod "$MODULE_NAME" 2>/dev/null || true
        continue
    fi

    # progress indicator every 10 cycles
    if (( i % 10 == 0 )); then
        echo -e "       ... $i / $CYCLES cycles completed  (${PASS_COUNT} pass, ${FAIL_COUNT} fail)"
    fi
done

# ---- capture final memory ---------------------------------------------------
echo -e "${INFO} Capturing final memory..."
MEM_AFTER=$(cat /proc/meminfo | grep -E '^MemFree|^MemAvailable' | tr '\n' ' ')
echo -e "       ${MEM_AFTER}"

# ---- analysis ---------------------------------------------------------------
echo ""
echo "============================================"
echo "  Memory Leak Test — Results"
echo "============================================"
echo "  Cycles attempted : ${CYCLES}"
echo "  Successful       : ${PASS_COUNT}"
echo "  Failed           : ${FAIL_COUNT}"
echo ""
echo "  Memory BEFORE: ${MEM_BEFORE}"
echo "  Memory AFTER : ${MEM_AFTER}"
echo ""

# Extract numeric values for comparison
BEFORE_FREE=$(echo "$MEM_BEFORE" | grep -oP 'MemFree:\s+\K[0-9]+')
AFTER_FREE=$(echo "$MEM_AFTER"  | grep -oP 'MemFree:\s+\K[0-9]+')

if [ -z "$BEFORE_FREE" ] || [ -z "$AFTER_FREE" ]; then
    echo -e "${FAIL} Could not parse MemFree values."
    echo "  Check /proc/meminfo manually:  cat /proc/meminfo | grep MemFree"
    exit 1
fi

DIFF=$((BEFORE_FREE - AFTER_FREE))

echo "  MemFree change  : ${DIFF} kB"

# Allow a small fluctuation (kilobytes).  A real leak would be in the
# megabytes range after 100 cycles.
THRESHOLD_KB=512

if [ "$DIFF" -lt "$THRESHOLD_KB" ]; then
    echo ""
    echo -e "${PASS} No significant memory leak detected (MemFree delta = ${DIFF} kB < ${THRESHOLD_KB} kB threshold)"
    echo ""
    echo "============================================"
    exit 0
else
    echo ""
    echo -e "${FAIL} POSSIBLE MEMORY LEAK DETECTED!"
    echo "  MemFree decreased by ${DIFF} kB (threshold: ${THRESHOLD_KB} kB)"
    echo "  This may indicate the module is not freeing all allocated memory on unload."
    echo ""
    echo "  Further diagnosis:"
    echo "    sudo cat /sys/kernel/debug/kmemleak"
    echo "    sudo cat /proc/slabinfo | grep kmalloc"
    echo "============================================"
    exit 1
fi
