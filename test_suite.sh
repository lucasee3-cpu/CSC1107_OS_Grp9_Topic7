#!/bin/bash
# =============================================================================
#  test_suite.sh — Master Test Suite Runner (Enhanced)
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  Runs ALL tests in sequence, times each test, captures results,
#  and generates a formatted markdown report at the end.
#
#  Tests executed:
#    1. Sanity Check    — 10 rapid checks (build, insmod, read, rmmod, clean)
#    2. Memory Leak     — load/unload cycling with /proc/meminfo analysis
#    3. Race Conditions — parallel reader/writer concurrency stress test
#    4. Boundary Values — threshold detection, one-shot guard, zero-length I/O
#    5. Performance     — insmod/rmmod/read latency and throughput benchmark
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
REPORT_FILE="${RESULT_DIR}/TEST_REPORT.md"
TIMING_FILE="${RESULT_DIR}/timing.txt"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
SUITE_START=$(date +%s)

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

# ---- helper: run one test with timing --------------------------------------
run_test() {
    local test_name="$1"
    local test_script="$2"
    local test_args="${3:-}"

    echo -n "  ${test_name} ... "

    if [ ! -f "$test_script" ]; then
        echo -e "${SKIP} (script not found: ${test_script})"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo "SKIP ${test_name} — script not found" >> "$RESULTS_FILE"
        echo "0 ${test_name} SKIP" >> "$TIMING_FILE"
        return
    fi

    sudo rmmod sdhealth 2>/dev/null || true
    sleep 1

    local test_start=$(date +%s)
    local exit_code=0
    bash "$test_script" $test_args > "${RESULT_DIR}/${test_name}.log" 2>&1 || exit_code=$?
    local test_end=$(date +%s)
    local test_elapsed=$((test_end - test_start))

    echo "${test_elapsed} ${test_name}" >> "$TIMING_FILE"

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${PASS} (${test_elapsed}s)"
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "PASS ${test_name} (${test_elapsed}s)" >> "$RESULTS_FILE"
    else
        echo -e "${FAIL} (exit: ${exit_code}, ${test_elapsed}s)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "FAIL ${test_name} (exit: ${exit_code}, ${test_elapsed}s)" >> "$RESULTS_FILE"
        echo "  Last 5 lines:"
        tail -5 "${RESULT_DIR}/${test_name}.log" | sed 's/^/    /'
    fi
}

# ---- run tests -------------------------------------------------------------
echo "============================================"
echo "  Running Tests"
echo "============================================"
echo ""

# Test 1: Sanity Check (always quick)
run_test "Sanity Check"      "./sanity_check.sh"
# Sanity check runs make clean at the end — rebuild so other tests have sdhealth.ko
make 2>/dev/null || true

# Test 2: Memory Leak
if [ "$QUICK_MODE" -eq 1 ]; then
    run_test "Memory Leak (quick)"   "./test_memory_leak.sh"    "20"
else
    run_test "Memory Leak"           "./test_memory_leak.sh"    "100"
fi

# Test 3: Race Conditions
if [ "$QUICK_MODE" -eq 1 ]; then
    run_test "Race Conditions (quick)" "./test_race_conditions.sh" "4 10"
else
    run_test "Race Conditions"       "./test_race_conditions.sh" "16 30"
fi

# Test 4: Boundary Values
run_test "Boundary Values"   "./test_boundary_values.sh"

# Test 5: Performance
if [ "$QUICK_MODE" -eq 1 ]; then
    run_test "Performance (quick)"   "./test_performance.sh"    "10"
else
    run_test "Performance"           "./test_performance.sh"    "50"
fi

echo ""

# ---- capture dmesg snapshot ------------------------------------------------
echo -e "${INFO} Capturing dmesg snapshot..."
sudo dmesg > "$DMESG_FILE" 2>/dev/null || true

# ---- generate report -------------------------------------------------------
SUITE_END=$(date +%s)
SUITE_ELAPSED=$((SUITE_END - SUITE_START))
SUITE_MIN=$((SUITE_ELAPSED / 60))
SUITE_SEC=$((SUITE_ELAPSED % 60))
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))

# Build the markdown report
cat > "$REPORT_FILE" << REPORTEOF
# SD Card Health Monitor — Test Report

**CSC1107 Group 9 — Project 7**  
**Date:** $(date '+%Y-%m-%d %H:%M:%S')  
**Kernel:** $(uname -r)  
**Architecture:** $(uname -m)  
**Mode:** $([ "$QUICK_MODE" -eq 1 ] && echo "Quick" || echo "Full")  
**Duration:** ${SUITE_MIN}m ${SUITE_SEC}s  

---

## Results Summary

| Test | Result | Duration |
|------|--------|----------|
REPORTEOF

while read -r line; do
    elapsed=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
    result=$(grep "^PASS\|^FAIL\|^SKIP" "${RESULT_DIR}/results.txt" | grep "$name" | head -1 | awk '{print $1}')
    emoji=""
    case "$result" in
        PASS) emoji="✅" ;;
        FAIL) emoji="❌" ;;
        SKIP) emoji="⏭️" ;;
    esac
    echo "| $name | ${emoji} ${result} | ${elapsed}s |" >> "$REPORT_FILE"
done < "$TIMING_FILE"

cat >> "$REPORT_FILE" << REPORTEOF

---

## Verdict

REPORTEOF

if [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    echo "**✅ ALL TESTS PASSED**" >> "$REPORT_FILE"
    FINAL_EXIT=0
elif [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -eq 0 ]; then
    echo "**⚠️ NO TESTS EXECUTED**" >> "$REPORT_FILE"
    FINAL_EXIT=0
else
    echo "**❌ ${FAIL_COUNT} TEST(S) FAILED**" >> "$REPORT_FILE"
    FINAL_EXIT=1
fi

cat >> "$REPORT_FILE" << REPORTEOF

| Metric | Count |
|--------|-------|
| Total  | ${TOTAL} |
| Passed | ${PASS_COUNT} |
| Failed | ${FAIL_COUNT} |
| Skipped | ${SKIP_COUNT} |

---

## Diagnostic Information

- **dmesg snapshot:** \`${DMESG_FILE}\`
- **Full logs:** \`${RESULT_DIR}/\`
- **Kernel version:** $(uname -r)

### Recent [SDHEALTH] Kernel Messages

\`\`\`
$(sudo dmesg | grep '\[SDHEALTH\]' | tail -20)
\`\`\`

---

*Report generated by test_suite.sh — Member 5 (Faris)*
REPORTEOF

# ---- print summary ---------------------------------------------------------
echo "============================================"
echo "  Test Suite — Summary"
echo "============================================"
echo ""
echo "  Total   : ${TOTAL}"
echo -e "  Passed  : ${PASS_COUNT}  ${PASS}"
echo -e "  Failed  : ${FAIL_COUNT}  ${FAIL}"
echo -e "  Skipped : ${SKIP_COUNT}  ${SKIP}"
echo "  Time    : ${SUITE_MIN}m ${SUITE_SEC}s"
echo ""

if [ "$FINAL_EXIT" -eq 0 ]; then
    echo -e "  ${BOLD}${GREEN}VERDICT: ALL TESTS PASSED${NC}"
else
    echo -e "  ${BOLD}${RED}VERDICT: ${FAIL_COUNT} TEST(S) FAILED${NC}"
fi

echo ""
echo "  Report saved to: ${REPORT_FILE}"
echo "  Full logs:       ${RESULT_DIR}/"
echo "  dmesg snapshot:  ${DMESG_FILE}"
echo ""
echo "============================================"

exit "$FINAL_EXIT"

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

    timeout 10 sudo rmmod sdhealth 2>/dev/null || true
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
