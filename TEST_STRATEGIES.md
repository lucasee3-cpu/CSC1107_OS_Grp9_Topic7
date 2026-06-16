# SD Card Health Monitor — Test Strategy Brainstorming

**CSC1107 Group 9 — Project 7**  
**Role: Automation & Testing Lead (Member 5 — Faris)**

---

## 1. Race Condition Testing (Concurrency)

### 1.1 Motivation
The kernel module can be accessed simultaneously by multiple user-space processes via `/dev/sdhealth` read/write. The `update_stats()` function reads from `/sys/block/mmcblk0/stat` and updates global `static` counters — without any locking in the current skeleton. Simultaneous readers/writers could:

- Read partially-updated statistics (torn reads).
- Corrupt the `initial_reading` flag, resetting rate calculations.
- Cause the timer callback (`sd_timer_callback`) and a user-triggered `read()` to race on the same counters.

### 1.2 Proposed Test Methodologies

| # | Test Name | Approach |
|---|-----------|----------|
| 1 | **Parallel Reader Bombardment** | Spawn `N` processes (e.g., `N = 8, 16, 32`) that all `open("/dev/sdhealth")` → `read()` in a tight loop. Run for `T = 60` seconds. Collect output from each process into separate log files, then diff adjacent pairs — any divergence indicates a torn/inconsistent read. |
| 2 | **Reader-Writer Interleaving** | Launch one process that does continuous `write()` commands (changing thresholds or requesting stats) while `M` reader processes do continuous `read()`. Check that no reader ever sees a malformed string (e.g., missing fields, negative counts). |
| 3 | **Timer-vs-User Race** | Set the kernel timer interval to a very small value (e.g., `HZ/10`) using the `WRITE` path if supported, then hammer `read()` from user space. Monitor `dmesg` for kernel Oops, BUG, or WARN_ON splats that indicate a timer callback stepped on a user read. |
| 4 | **Open/Close Flood** | Rapidly open and close `/dev/sdhealth` from multiple threads. Verify that the module reference count never goes negative and that the device remains usable after the storm. |
| 5 | **Kernel Concurrency Sanitizer (KCSAN)** | Rebuild the kernel module with `CONFIG_KCSAN=y` if available on the Pi kernel, or use the Kernel Thread Sanitizer. This data-race detector will flag any unprotected concurrent access to the `static` counters. |

### 1.3 Tools
- Custom C test harness using `fork()` + `pthread`.
- Shell scripts wrapping `dd` and `cat` in parallel (`xargs -P`, GNU `parallel`).
- `stress-ng` with custom stressors.
- `dmesg -w` (live kernel log monitoring).

---

## 2. Boundary Value Analysis (Extreme I/O Loads)

### 2.1 Motivation
The detection subsystem on the `detection-logging` branch defines thresholds:

```c
#define WRITE_THRESHOLD  1000
#define READ_THRESHOLD   5000
```

The module should:
- Correctly trigger `KERN_WARNING` when thresholds are crossed.
- *Not* spam the log (it has a one-shot alert guard: `write_alert_sent` / `read_alert_sent`).
- Handle overflow of `unsigned long` counters on a 64-bit ARM platform (theoretical maximum `2^64` operations — impractical to reach but worth reasoning about).

### 2.2 Proposed Test Methodologies

| # | Test Name | Approach |
|---|-----------|----------|
| 1 | **Threshold Just-Below / At / Just-Above** | Generate exactly `THRESHOLD - 1`, `THRESHOLD`, and `THRESHOLD + 1` write operations by artificially writing a known number of sectors to the SD card (e.g., `dd if=/dev/zero of=/tmp/dummy bs=512 count=N`). After each run, check `dmesg` for the expected presence/absence of the "Excessive write" warning. |
| 2 | **Sustained Above-Threshold** | Run writes continuously at 2× threshold for 30 seconds. Verify that the alert fires exactly **once** (the one-shot guard works) and does not re-fire until the rate drops below threshold and rises again. |
| 3 | **Rapid Threshold Oscillation** | Alternate between low-I/O (idle) and high-I/O (burst) every 200 ms. Check that the alert toggles correctly (on → off → on) without duplicate firings within a single burst. |
| 4 | **Throughput Saturation** | Use `fio` or `dd` with `oflag=direct` to push the SD card to its maximum write throughput. Simultaneously run `./monitor` to see if the reported `WRITE_KBps` saturates at a physically plausible value and does not wrap around. |
| 5 | **Counter Overflow Reasoning** | Document the expected behaviour if `READ_count` or `WRITE_count` approaches `ULONG_MAX`. On ARM64 `unsigned long` is 64-bit → overflow at ~1.8×10^19 operations. This is practically unreachable on an SD card (typical endurance ~10^5 P/E cycles × capacity). Conclude whether a wrap guard is needed. |
| 6 | **Zero-Length I/O** | Issue `read(fd, buf, 0)` and `write(fd, buf, 0)` — the module should handle zero-length requests gracefully (return 0, not -EINVAL or crash). |

### 2.3 Tools
- `dd` with various `bs` and `count` values for controlled I/O injection.
- `fio` (Flexible I/O Tester) for sustained throughput tests.
- Custom shell loop: `for i in $(seq 1 N); do dd ...; done`.
- `dmesg -c` (read + clear kernel log) between test runs.

---

## 3. Dynamic Memory Analysis (Memory Leaks)

### 3.1 Motivation
Kernel memory leaks are especially dangerous because:
- There is no garbage collector; leaked memory is permanently lost until reboot.
- The module does dynamic allocations: `alloc_chrdev_region`, `cdev_init`/`cdev_add`, `class_create`, `device_create`, `timer_setup`.
- The `detection.c` subsystem has a static circular buffer (`event_log[50][128]`) — fine, but any future dynamic-allocation changes must be verified.
- `filp_open` / `filp_close` in `update_stats()` must always be paired.

### 3.2 Proposed Test Methodologies

| # | Test Name | Approach |
|---|-----------|----------|
| 1 | **Load/Unload Cycle Test** | Run a loop of `insmod sdhealth.ko` → wait 5 seconds → `rmmod sdhealth` for `N = 1000` iterations. Capture `cat /proc/meminfo` (or `free -m`) before and after. Any monotonic decrease in free memory indicates a leak. |
| 2 | **Kernel Memory Leak Detector (kmemleak)** | Enable `CONFIG_DEBUG_KMEMLEAK=y` in the kernel config (or check if already enabled on the Pi). After each test run: `echo scan > /sys/kernel/debug/kmemleak` then `cat /sys/kernel/debug/kmemleak`. Any unfreed allocation attributed to `sdhealth` is a leak. |
| 3 | **Slab Allocator Inspection** | Before and after a heavy test run, compare `/proc/slabinfo` for the `kmalloc-*` cache sizes the module uses. A growing slab with no corresponding shrink after `rmmod` indicates a leak. |
| 4 | **Open/Close Leak Check** | Open `/dev/sdhealth` `N = 10000` times without closing (or close only half). Then `rmmod` the module. If `rmmod` fails with "Module is in use" despite all user processes having exited, a file-reference leak exists. If it succeeds, check `/proc/meminfo` for leaked memory. |
| 5 | **Timer Teardown Verification** | Ensure `del_timer_sync(&sd_timer)` is called in `sdhealth_exit()`. Test: load module → immediately unload before the first timer tick fires. If the kernel panics or hangs, the timer cleanup is buggy. Repeat 100 times. |
| 6 | **Static Analysis with Sparse / Coccinelle** | Run the Linux kernel static analysis tools (`make C=2` for Sparse, or Coccinelle scripts) over the module source to catch:
    - `kmalloc` without matching `kfree`
    - `filp_open` without matching `filp_close`
    - Unbalanced `class_create` / `class_destroy` pairs |

### 3.3 Tools
- `kmemleak` (kernel built-in).
- `/proc/meminfo`, `/proc/slabinfo`.
- `valgrind` (user-space only; for `monitor.c` leak checks).
- Linux kernel `sparse` checker (`make C=2`).
- Custom Bash wrapper for load/unload cycling.

---

## 4. Integration & Regression Test Pipeline

### 4.1 Proposed CI Flow

```
[Push to automation-testing]
        │
        ▼
[Build on Pi: make]
        │
        ▼
[Insmod + chmod: run.sh]
        │
        ▼
[Race Condition Tests]
        │
        ▼
[Boundary Value Tests]
        │
        ▼
[Memory Leak Tests]
        │
        ▼
[Cleanup: cleanup.sh]
        │
        ▼
[Report: pass/fail + dmesg excerpts]
```

### 4.2 Test Harness Script (Future)

A master test runner `test_suite.sh` that:
1. Sources `run.sh` for setup.
2. Runs each test category sequentially.
3. Captures `dmesg` output after each test.
4. Produces a coloured pass/fail summary.
5. Calls `cleanup.sh` at the end (even on failure, via `trap`).

---

## 5. Notes for Fellow Team Members

| Member | Role | What Testing Needs From You |
|--------|------|-----------------------------|
| 1 | Kernel Driver | Stable `sdhealth_main.c` with consistent `printk` tags (`[SDHEALTH]`) |
| 2 | Detection & Logging | `detection.h` with clear threshold `#define`s; `print_event_logs()` function |
| 3 | User-Space Comms | `monitor.c` with a non-interactive mode flag (e.g., `--once`) for automated testing |
| 4 | Stats Integration | Consistent data format returned by `read()` so test scripts can parse it |

---

*Last updated: 2026-06-16 — Member 5 (Faris)*
