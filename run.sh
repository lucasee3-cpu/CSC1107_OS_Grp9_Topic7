#!/bin/bash
# =============================================================================
#  run.sh — SD Card Health Monitor Automation Script
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  What this script does:
#    1. Runs 'make' to compile the kernel module (sdhealth.ko) and the
#       user-space monitor program (monitor).
#    2. Inserts the compiled kernel module into the Linux kernel via insmod.
#    3. Sets read/write permissions on the /dev/sdhealth device node so
#       the user-space monitor can communicate with the driver without root.
#    4. Launches the interactive user-space monitor program.
#
#  Usage:  ./run.sh
#  Requires: sudo access for insmod and chmod
# =============================================================================

set -euo pipefail

# ---- colour helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'   # No Colour

echo_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- step 1: build everything ----------------------------------------------
echo_info "Step 1/4 — Building kernel module and user-space monitor..."
if make; then
    echo_info "Build completed successfully."
else
    echo_error "Build failed — check compiler errors above."
    exit 1
fi

# ---- step 2: insert kernel module ------------------------------------------
echo_info "Step 2/4 — Inserting sdhealth.ko into the kernel..."
if lsmod | grep -q "^sdhealth"; then
    echo_warn "sdhealth module is already loaded — removing it first."
    timeout 10 sudo rmmod sdhealth 2>/dev/null || true
fi
timeout 10 sudo insmod sdhealth.ko
echo_info "Module loaded.  Verify:  lsmod | grep sdhealth"

# ---- step 3: set device permissions ----------------------------------------
echo_info "Step 3/4 — Setting permissions on /dev/sdhealth..."
# Allow any user to read/write the device node (needed so ./monitor works
# without requiring root for every execution).
if [ -e /dev/sdhealth ]; then
    sudo chmod 666 /dev/sdhealth
    echo_info "Permissions set: $(ls -l /dev/sdhealth)"
else
    echo_error "/dev/sdhealth not found — did the module load correctly?"
    echo_error "Check dmesg:  sudo dmesg | tail -20"
    exit 1
fi

# ---- step 4: run the user-space monitor ------------------------------------
echo_info "Step 4/4 — Launching user-space monitor..."
echo ""
./monitor

# ---- done ------------------------------------------------------------------
echo ""
echo_info "run.sh finished.  Use ./cleanup.sh to remove the module."
