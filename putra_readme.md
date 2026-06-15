# Member 3 – User Space Monitor (`monitor.c`)

## Overview

`monitor.c` is the user-space application that communicates with the
`sdhealth` kernel module through `/dev/sdhealth`. It provides a simple
numbered menu interface allowing the user to view live SD card statistics,
check kernel anomaly logs, change the refresh rate, and exit cleanly.

This program is Member 3's contribution to the project. It sits on the
user-space side of the kernel-user boundary and owns the `read()` and
`write()` system calls.

---

## How it fits into the project

```
Kernel space (always running)
─────────────────────────────────────────────────────────
sd_timer_callback()        fires every 1 second
  └── schedules sd_work_handler() via workqueue
        └── update_stats()        reads /sys/block/mmcblk0/stat
        └── check_anomaly()       Member 4's anomaly detection
        └── printk()              logs rates to dmesg

User space (when monitor is running)
─────────────────────────────────────────────────────────
monitor.c  (Member 3)
  │
  ├── write() ──► [SDHEALTH] kernel module receives "REQUEST_STATS"
  │                          logs it via printk()
  │
  ├── read()  ◄── kernel serves latest stats computed by the timer
  │
  └── Option 2: dmesg | grep [SDHEALTH]
                 surfaces Member 4's anomaly alerts to the user
```

---

## How to compile

```bash
gcc -o monitor monitor.c
```

## How to run

The kernel module must be loaded first:

```bash
make
sudo insmod sdhealth.ko
sudo ./monitor
```

---

## Menu options

```
1. View SD card stats      — polls /dev/sdhealth every N seconds
2. View kernel log         — shows [SDHEALTH] messages from dmesg
3. Change refresh rate     — set polling interval (1–60 seconds)
4. Exit                    — clean shutdown
```

### Option 1 — View SD card stats

Polls `/dev/sdhealth` in a loop at the chosen refresh rate. Each iteration:

1. Opens `/dev/sdhealth` with `O_RDWR`
2. Sends `write()` with command string `"REQUEST_STATS"` to the kernel
3. Receives stats back via `read()`
4. Displays the stats and waits before the next poll
5. Closes the device

The device is opened and closed every poll instead of using `lseek()`,
because character devices do not support seeking. Reopening resets the
file offset to 0, which is required for the kernel's `sdhealth_read()`
to return fresh data instead of EOF.

Press `Ctrl+C` to stop polling and return to the main menu.

**Example output:**
```
SD Health Monitor
Reads          : 10673
Writes         : 726
Read rate      : 5/sec
Write rate     : 2/sec
Read throughput: 12 KB/s
Write throughput: 4 KB/s
Read sectors   : 972800
Write sectors  : 16384
```

### Option 2 — View kernel log

Runs the following shell command internally:

```bash
dmesg | grep '\[SDHEALTH\]' | tail -15
```

This surfaces all kernel-side logs from the module — including Member 1's
timer updates, the write() commands received from user space, and
critically, Member 4's anomaly detection alerts — without the user
needing to type anything themselves.

**Example output:**
```
[14829.703608] [SDHEALTH] Device opened
[14829.703631] [SDHEALTH] Received from user space: REQUEST_STATS
[14829.703710] [SDHEALTH] Read statistics sent to user space
[14829.703731] [SDHEALTH] Device closed
[14830.701224] [SDHEALTH] Timer updated: Read rate: 5 and Write rate: 2
[14830.701225] [SDHEALTH] WARNING: Excessive read activity detected (10673 reads)
```

### Option 3 — Change refresh rate

Prompts for a new polling interval. Accepts values between 1 and 60
seconds. Invalid values are rejected and the current rate is kept.

### Option 4 — Exit

Closes the program cleanly. `Ctrl+C` from the main menu also exits.

---

## Changes made to other files

### `sdhealth_main.c` (Member 1's file) — major update

Member 1 significantly updated `sdhealth_main.c` during development.
The following changes were made in coordination:

**1. Added kernel workqueue to fix `filp_open()` crash**

The original code called `update_stats()` directly inside
`sd_timer_callback()`. Timer callbacks run in softirq (interrupt) context
where `filp_open()` is not safe to call — it needs process context to
acquire locks and potentially sleep. This caused intermittent
`Failed to open /sys/block/mmcblk0/stat` errors.

The fix introduces a workqueue that bridges the two contexts:

```
sd_timer_callback()   ← softirq context (cannot call filp_open)
  └── schedule_work() ← safe to call from softirq
        └── sd_work_handler()  ← runs in process context
              └── filp_open()  ← now safe
```

Changes made:
- Added `#include <linux/workqueue.h>`
- Added `static struct work_struct sd_work`
- Added `sd_work_handler()` function containing `update_stats()` and `printk()`
- Changed `sd_timer_callback()` to call `schedule_work()` instead of `update_stats()` directly
- Added `INIT_WORK(&sd_work, sd_work_handler)` in `sdhealth_init()`
- Added `cancel_work_sync(&sd_work)` in `sdhealth_exit()` for clean shutdown
- Changed `del_timer_sync()` to `timer_delete_sync()` (renamed in newer kernels)

**2. Added `check_anomaly()` call inside `sd_work_handler()`**

Member 1's updated version removed the `check_anomaly()` call from
`sdhealth_read()`. It was added back into `sd_work_handler()` so
anomaly detection runs every second via the timer:

```c
static void sd_work_handler(struct work_struct *w)
{
    update_stats();
    check_anomaly(READ_count, WRITE_count);  // ← runs every second
    printk(KERN_INFO "[SDHEALTH] Timer updated...");
}
```

Also ensured `#include "detection.h"` is present at the top.

**3. Removed `update_stats()` from `sdhealth_read()`**

Since the timer now handles all stat updates exclusively, calling
`update_stats()` from `sdhealth_read()` as well was redundant and
caused a race condition. `sdhealth_read()` now just serves the most
recently computed values from the timer.

**4. Fixed `%*lu` → `%*u` in `sscanf`**

The kernel's `sscanf` does not support `%*lu` (assignment suppression
with length modifier together) and produced compiler warnings. Changed
all skipped fields to use `%*u` instead.

**5. Expanded stats output**

Member 2 added rate and throughput calculations to the stats string:

| Stat | Description |
|------|-------------|
| Read rate | Operations per second since last timer tick |
| Write rate | Operations per second since last timer tick |
| Read throughput | KB/s since last timer tick |
| Write throughput | KB/s since last timer tick |
| Read sectors | Total 512-byte sectors read |
| Write sectors | Total 512-byte sectors written |

### `detection.c` (Member 4's file)

`printk` comma bug fixed — commas removed after `KERN_INFO`,
`KERN_WARNING`, and `KERN_ERR`. No logic or threshold changes were made.

```c
// BEFORE (compile error)
printk(KERN_WARNING, "[SDHEALTH] WARNING: ...\n");

// AFTER (correct)
printk(KERN_WARNING "[SDHEALTH] WARNING: ...\n");
```

---

## Notes for the demo

- To trigger the **read warning** (threshold: 5,000 reads), just load the
  module — reads will already exceed this on a used Pi.
- To trigger the **write warning** (threshold: 1,000 writes), run:
  ```bash
  dd if=/dev/urandom of=/tmp/testfile bs=1M count=200
  ```
- To trigger the **critical warning** (threshold: 10,000 writes),
  temporarily lower `WRITE_THRESHOLD` in `detection.c` to 100 for the
  demo, then restore it afterwards.
- To see anomaly alerts fresh, reload the module first:
  ```bash
  sudo rmmod sdhealth && sudo insmod sdhealth.ko
  ```
- To verify everything is working end to end:
  ```bash
  sudo dmesg | grep '\[SDHEALTH\]' | tail -20
  ```
  You should see timer updates, REQUEST_STATS received, stats sent, and
  anomaly warnings all appearing together.
