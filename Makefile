# =============================================================================
#  SD Card Health Monitoring Block Driver — Build System
#  CSC1107 Group 9 — Project 7
#  Automation & Testing: Member 5 (Faris)
# =============================================================================
#
#  This Makefile compiles:
#    1. The Loadable Kernel Module  (sdhealth.ko)
#    2. The user-space monitor      (monitor)
#
#  The kernel module is built from up to two source files so the work of
#  Members 1–4 can merge cleanly:
#      sdhealth_main.c  — main driver logic   (Member 1 / Member 2)
#      detection.c      — anomaly detection   (Member 2)
#      detection.h      — detection interface (Member 2)
#
#  If the multi-file sources are absent the Makefile falls back to the
#  single-file sdhealth.c on the main branch.
# =============================================================================

# ---- detect which source layout is present --------------------------------
# $(src) is set by the kernel build system to the directory containing this
# Makefile.  Fall back to $(CURDIR) when invoked directly (e.g. 'make clean').
MY_SRC_DIR := $(if $(src),$(src),$(CURDIR))

SDHEALTH_MAIN := $(wildcard $(MY_SRC_DIR)/sdhealth_main.c)
DETECTION_C   := $(wildcard $(MY_SRC_DIR)/detection.c)
SINGLE_SRC    := $(wildcard $(MY_SRC_DIR)/sdhealth.c)

ifneq ($(SDHEALTH_MAIN)$(DETECTION_C),)
  # multi-file layout (matches detection-logging / kernel-user-comms branches)
  obj-m           += sdhealth.o
  sdhealth-objs   := sdhealth_main.o detection.o
else ifneq ($(SINGLE_SRC),)
  # single-file fallback (current main branch)
  obj-m           += sdhealth.o
else
  $(error No kernel source found in $(MY_SRC_DIR). Expected sdhealth_main.c+detection.c or sdhealth.c)
endif

# ---- user-space monitor ----------------------------------------------------
USER_BIN     := monitor
USER_SRC     := monitor.c

# ---- targets ---------------------------------------------------------------
.PHONY: all clean monitor help

all: $(USER_BIN)
	@echo "[BUILD] Compiling kernel module..."
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
	@echo "[BUILD] Done → sdhealth.ko + $(USER_BIN)"

$(USER_BIN): $(USER_SRC)
	@echo "[BUILD] Compiling user-space monitor..."
	gcc -Wall -Wextra -O2 -o $@ $<
	@echo "[BUILD] $(USER_BIN) built successfully"

clean:
	@echo "[CLEAN] Removing kernel build artifacts..."
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean 2>/dev/null || true
	@echo "[CLEAN] Removing user-space binary..."
	rm -f $(USER_BIN)
	rm -f *.o *.mod *.mod.c *.mod.o .*.cmd .*.d Module.symvers modules.order
	@echo "[CLEAN] Done"

help:
	@echo "============================================"
	@echo " SD Health Monitor — Build System"
	@echo "============================================"
	@echo "  make          Build kernel module + monitor"
	@echo "  make clean    Remove all build artifacts"
	@echo "  ./run.sh      Build, load module, run monitor"
	@echo "  ./cleanup.sh  Stop monitor, unload module, clean"
	@echo "============================================"
