#!/bin/bash
# =============================================================================
#  cleanup.sh — SD Card Health Monitor Cleanup Script
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this script does:
#    1. Terminates any running instance of the user-space monitor.
#    2. Removes the sdhealth kernel module from the kernel via rmmod.
#    3. Runs 'make clean' to delete all compiled binaries and artifacts.
#
#  Usage:  ./cleanup.sh
#  Requires: sudo access for rmmod
# =============================================================================

set -euo pipefail

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- step 1: terminate user-space monitor ----------------------------------
echo_info "Step 1/3 — Terminating user-space monitor (if running)..."
if pgrep -f "./monitor" > /dev/null 2>&1; then
    pkill -f "./monitor" && echo_info "Monitor process terminated." \
        || echo_warn "pkill returned non-zero but process may already be gone."
elif pgrep -f "monitor" > /dev/null 2>&1; then
    pkill -f "monitor" && echo_info "Monitor process terminated." \
        || echo_warn "pkill returned non-zero but process may already be gone."
else
    echo_info "No monitor process found — nothing to kill."
fi

# ---- step 2: remove kernel module ------------------------------------------
echo_info "Step 2/3 — Removing sdhealth kernel module..."
if lsmod | grep -q "^sdhealth"; then
    timeout 10 sudo rmmod sdhealth && echo_info "Module sdhealth removed." \
        || echo_error "Failed to remove sdhealth. Is a process still using /dev/sdhealth?"
else
    echo_info "sdhealth module is not loaded — nothing to remove."
fi

# ---- step 3: clean build artifacts -----------------------------------------
echo_info "Step 3/3 — Cleaning build artifacts..."
make clean 2>/dev/null || true
echo_info "Cleanup complete."
