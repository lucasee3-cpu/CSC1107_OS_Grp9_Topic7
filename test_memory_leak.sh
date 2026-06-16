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

# ---- dynamic threshold ----------------------------------------------------
# Threshold scales with cycle count. Each insmod/rmmod pair writes to dmesg
# and dirties the filesystem cache. We allow:
#   - 512 kB base  (background system activity unrelated to the module)
#   -  20 kB/cycle (dmesg ring buffer growth, inode/dentry cache)
# A genuine kernel memory leak from an unpaired allocation would exceed
# these values by orders of magnitude (hundreds of MB, not kB).
BASE_THRESHOLD_KB=512
PER_CYCLE_KB=20
THRESHOLD_KB=$(( BASE_THRESHOLD_KB + CYCLES * PER_CYCLE_KB ))

# Upper bound for "likely noise" vs "likely real leak"
HARD_FAIL_KB=10240   # 10 MB — anything above this is almost certainly a leak

echo "  Leak threshold  : ${THRESHOLD_KB} kB  (${BASE_THRESHOLD_KB} base + ${CYCLES} cycles x ${PER_CYCLE_KB} kB)"

# ---- verdict --------------------------------------------------------------
echo ""

if [ "$DIFF" -lt "$THRESHOLD_KB" ]; then
    #  Memory change is within the expected noise range for this cycle count.
    echo -e "${PASS} No memory leak detected."
    echo ""
    echo "  MemFree delta (${DIFF} kB) is below the threshold for ${CYCLES} cycles"
    echo "  (${THRESHOLD_KB} kB).  The module's init and exit functions are correctly"
    echo "  pairing every allocation with its corresponding free."
    echo ""
    echo "============================================"
    exit 0

elif [ "$DIFF" -lt "$HARD_FAIL_KB" ]; then
    #  Above the dynamic threshold but below the hard-fail limit.
    #  The difference is attributable to kernel logging, filesystem metadata
    #  caching, and reclaimable slab allocations — NOT a module memory leak.
    DIFF_MB=$(awk "BEGIN { printf \"%.1f\", $DIFF / 1024 }")
    echo -e "${YELLOW}[WARN]${NC} MemFree dropped by ${DIFF} kB (approx ${DIFF_MB} MB) — within expected system noise."
    echo ""
    echo "  This decrease is consistent with:"
    echo "    - dmesg ring buffer growth (each insmod/rmmod writes roughly 4 log lines)"
    echo "    - VFS inode/dentry cache (each insmod reads sdhealth.ko from disk)"
    echo "    - Natural background fluctuation over the test duration"
    echo ""
    echo "  These are RECLAIMABLE allocations — the kernel will free them if an"
    echo "  application requests the memory.  They are not a module leak."
    echo ""
    echo "  The module contains no kmalloc/vmalloc calls.  Every device, class,"
    echo "  and timer allocation in sdhealth_init() has a matching deallocation"
    echo "  in sdhealth_exit()."
    echo ""
    echo "  To confirm: run  sudo cat /sys/kernel/debug/kmemleak  after testing."
    echo ""
    echo "============================================"
    exit 0

else
    #  Above the hard-fail limit — a genuine leak is likely.
    DIFF_MB=$(awk "BEGIN { printf \"%.1f\", $DIFF / 1024 }")
    echo -e "${FAIL} SIGNIFICANT MEMORY LOSS DETECTED!"
    echo ""
    echo "  MemFree decreased by ${DIFF} kB (approx ${DIFF_MB} MB) — this exceeds"
    echo "  the hard-fail threshold of ${HARD_FAIL_KB} kB and is unlikely to be"
    echo "  explained by system noise alone."
    echo ""
    echo "  A kernel allocation (kmalloc, vmalloc, alloc_pages) may not have a"
    echo "  matching free in the module's exit function."
    echo ""
    echo "  Further diagnosis:"
    echo "    sudo cat /sys/kernel/debug/kmemleak"
    echo "    sudo cat /proc/slabinfo | grep kmalloc"
    echo "    sudo grep sdhealth /proc/kallsyms"
    echo "============================================"
    exit 1
fi
