#!/bin/bash
# =============================================================================
#  test_suite.sh — Master Test Suite Runner
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this script does:
#    Runs all individual test scripts in sequence, captures results,
#    and produces a single pass/fail summary report.  The test suite
#    ensures:
#      - The module is built before testing.
#      - Each test runs from a clean state (module loaded/unloaded).
#      - dmesg output is captured for diagnostic evidence.
#      - Cleanup is performed even if tests fail (via trap handler).
#
#  Usage:  ./test_suite.sh [--quick]
#          --quick  =  run reduced cycles for faster feedback
# =============================================================================

set -euo pipefail

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}PASS${NC}"
FAIL="${RED}FAIL${NC}"
SKIP="${YELLOW}SKIP${NC}"
INFO="${CYAN}[INFO]${NC}"

# ---- configuration ---------------------------------------------------------
QUICK_MODE=0
if [ "${1:-}" = "--quick" ]; then
    QUICK_MODE=1
fi

RESULT_DIR="/tmp/sdhealth_test_suite_$$"
RESULTS_FILE="${RESULT_DIR}/results.txt"
DMESG_FILE="${RESULT_DIR}/dmesg_snapshot.txt"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# ---- cleanup trap ----------------------------------------------------------
cleanup() {
    echo ""
    echo -e "${INFO} Test suite cleanup..."
    if [ -f "./cleanup.sh" ]; then
        bash ./cleanup.sh 2>/dev/null || true
    else
        sudo rmmod sdhealth 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ---- setup -----------------------------------------------------------------
mkdir -p "$RESULT_DIR"

echo "============================================"
echo "  SD Card Health Monitor — Test Suite"
echo "  CSC1107 Group 9 — Project 7"
echo "  $(date)"
if [ "$QUICK_MODE" -eq 1 ]; then
    echo "  MODE: Quick (reduced cycles)"
else
    echo "  MODE: Full"
fi
echo "============================================"
echo ""

# ---- pre-flight: build -----------------------------------------------------
echo -e "${INFO} Building project..."
if make 2>&1 | tail -3; then
    echo -e "       Build: ${PASS}"
else
    echo -e "       Build: ${FAIL} — cannot continue."
    exit 1
fi

echo ""

# ---- helper: run one test --------------------------------------------------
run_test() {
    local test_name="$1"
    local test_script="$2"
    local test_args="${3:-}"

    echo -n "  ${test_name} ... "

    if [ ! -f "$test_script" ]; then
        echo -e "${SKIP} (script not found: ${test_script})"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo "SKIP ${test_name} — script not found" >> "$RESULTS_FILE"
        return
    fi

    sudo rmmod sdhealth 2>/dev/null || true
    sleep 1

    local exit_code=0
    bash "$test_script" $test_args > "${RESULT_DIR}/${test_name}.log" 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${PASS}"
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "PASS ${test_name}" >> "$RESULTS_FILE"
    else
        echo -e "${FAIL} (exit code: ${exit_code})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "FAIL ${test_name} (exit code: ${exit_code})" >> "$RESULTS_FILE"
        echo "  Last 5 lines of output:"
        tail -5 "${RESULT_DIR}/${test_name}.log" | sed 's/^/    /'
    fi
}

# ---- run tests -------------------------------------------------------------
echo "============================================"
echo "  Running Tests"
echo "============================================"
echo ""

if [ "$QUICK_MODE" -eq 1 ]; then
    run_test "Memory Leak (quick)"   "./test_memory_leak.sh"    "20"
else
    run_test "Memory Leak"           "./test_memory_leak.sh"    "100"
fi

if [ "$QUICK_MODE" -eq 1 ]; then
    run_test "Race Conditions (quick)" "./test_race_conditions.sh" "4 10"
else
    run_test "Race Conditions"       "./test_race_conditions.sh" "16 30"
fi

run_test "Boundary Values"       "./test_boundary_values.sh"

echo ""

# ---- capture dmesg snapshot ------------------------------------------------
echo -e "${INFO} Capturing dmesg snapshot..."
sudo dmesg > "$DMESG_FILE" 2>/dev/null || true

# ---- summary ---------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))

echo "============================================"
echo "  Test Suite — Summary"
echo "============================================"
echo ""
echo "  Total  : ${TOTAL}"
echo -e "  Passed : ${PASS_COUNT}  ${PASS}"
echo -e "  Failed : ${FAIL_COUNT}  ${FAIL}"
echo -e "  Skipped: ${SKIP_COUNT}  ${SKIP}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    echo -e "  ${BOLD}${GREEN}VERDICT: ALL TESTS PASSED${NC}"
    FINAL_EXIT=0
elif [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -eq 0 ]; then
    echo -e "  ${BOLD}${YELLOW}VERDICT: NO TESTS EXECUTED${NC}"
    FINAL_EXIT=0
else
    echo -e "  ${BOLD}${RED}VERDICT: ${FAIL_COUNT} TEST(S) FAILED${NC}"
    FINAL_EXIT=1
fi

echo ""
echo "  Full logs:     ${RESULT_DIR}/"
echo "  dmesg snapshot: ${DMESG_FILE}"
echo "  Results:        ${RESULTS_FILE}"
echo ""
echo "============================================"

exit "$FINAL_EXIT"
