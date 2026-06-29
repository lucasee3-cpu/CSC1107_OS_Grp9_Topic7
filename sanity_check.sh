#!/bin/bash
# =============================================================================
#  sanity_check.sh — Quick Smoke Test (30 seconds)
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  A fast pass/fail check that verifies the entire pipeline works.
#  Runs in under 30 seconds.  Use this before every commit or after
#  any source code change to catch regressions immediately.
#
#  Usage:  ./sanity_check.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS="${GREEN}PASS${NC}"
FAIL="${RED}FAIL${NC}"
INFO="${CYAN}[INFO]${NC}"

PASS_COUNT=0
FAIL_COUNT=0
START_TIME=$(date +%s)

# ---- helper -----------------------------------------------------------------
check() {
    local name="$1"
    echo -n "  $name ... "
}

pass() {
    echo -e "${PASS}"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    local reason="${1:-}"
    echo -e "${FAIL} ${reason}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---- header -----------------------------------------------------------------
echo "============================================"
echo "  SD Health Monitor — Sanity Check"
echo "  $(date)"
echo "============================================"
echo ""

# ---- 1: build --------------------------------------------------------------
check "Build kernel module + monitor"
if make 2>&1 | tail -1 | grep -q "Done"; then
    pass
else
    fail "build failed — check compiler errors"
fi

# ---- 2: insmod --------------------------------------------------------------
check "Insert kernel module"
sudo rmmod sdhealth 2>/dev/null || true
if timeout 10 sudo insmod sdhealth.ko 2>/dev/null; then
    pass
else
    fail "insmod failed — check dmesg"
fi

# ---- 3: device node ---------------------------------------------------------
check "Device /dev/sdhealth exists"
if [ -e /dev/sdhealth ]; then
    pass
else
    fail "/dev/sdhealth not found"
fi

# ---- 4: permissions ---------------------------------------------------------
check "Set device permissions"
sudo chmod 666 /dev/sdhealth 2>/dev/null
PERMS=$(stat -c '%a' /dev/sdhealth 2>/dev/null || echo "")
if [ "$PERMS" = "666" ]; then
    pass
else
    fail "permissions are $PERMS (expected 666)"
fi

# ---- 5: read stats ----------------------------------------------------------
check "Read statistics from device"
STATS=$(timeout 5 sudo cat /dev/sdhealth 2>/dev/null || echo "")
if echo "$STATS" | grep -q "SD Health Monitor"; then
    pass
else
    fail "could not read stats from /dev/sdhealth"
fi

# ---- 6: kernel log output ---------------------------------------------------
check "Kernel log contains [SDHEALTH] messages"
if sudo dmesg | grep -q '\[SDHEALTH\]'; then
    pass
else
    fail "no [SDHEALTH] messages in dmesg"
fi

# ---- 7: detection -----------------------------------------------------------
check "Anomaly detection check_anomaly() called"
if sudo dmesg | grep -q 'check_anomaly()'; then
    pass
else
    fail "check_anomaly() not found in dmesg — detection may not be running"
fi

# ---- 8: rmmod ---------------------------------------------------------------
check "Remove kernel module"
if timeout 10 sudo rmmod sdhealth 2>/dev/null; then
    pass
else
    fail "rmmod failed — module may be stuck"
fi

# ---- 9: clean build artifacts -----------------------------------------------
check "Clean build artifacts"
if make clean 2>&1 | grep -q "Done"; then
    pass
else
    fail "make clean did not complete"
fi

# ---- 10: no stray files -----------------------------------------------------
check "No stray kernel objects"
STRAY=$(ls *.ko 2>/dev/null | wc -l)
STRAY=$(echo "$STRAY" | tr -d ' ')
if [ "$STRAY" -eq 0 ] 2>/dev/null; then
    pass
else
    fail "$STRAY .ko file(s) still present"
fi

# ---- summary ----------------------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
TOTAL=$((PASS_COUNT + FAIL_COUNT))

echo ""
echo "============================================"
echo "  Sanity Check — Results"
echo "============================================"
echo "  Checks  : $TOTAL"
echo -e "  Passed  : ${PASS_COUNT} ${PASS}"
echo -e "  Failed  : ${FAIL_COUNT} ${FAIL}"
echo "  Time    : ${ELAPSED}s"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}ALL CHECKS PASSED — project is healthy${NC}"
    echo "============================================"
    exit 0
else
    echo -e "  ${RED}${FAIL_COUNT} CHECK(S) FAILED — review output above${NC}"
    echo "============================================"
    exit 1
fi
