# Automation & Testing Lead — Complete Knowledge Reference

**CSC1107 Group 9 — Project 7: SD Card Health Monitoring Block Driver**  
**Member 5 (Faris) — Branch: `automation-testing`**  
**Compiled: 2026-06-16**

---

## Table of Contents

1. [Your Role in the Project](#1-your-role-in-the-project)
2. [Key Terminology — Formal Definitions](#2-key-terminology--formal-definitions)
3. [Files You Created on This Branch](#3-files-you-created-on-this-branch)
4. [The `Makefile` — Line-by-Line Explanation](#4-the-makefile--line-by-line-explanation)
5. [The `run.sh` Script — Step-by-Step Execution Trace](#5-the-runsh-script--step-by-step-execution-trace)
6. [The `cleanup.sh` Script — Step-by-Step Execution Trace](#6-the-cleanupsh-script--step-by-step-execution-trace)
7. [The `monitor.c` Skeleton — Code Walkthrough](#7-the-monitorc-skeleton--code-walkthrough)
8. [The `TEST_STRATEGIES.md` Document — Future Planning](#8-the-test_strategiesmd-document--future-planning)
9. [Complete Execution Flow — End-to-End Sequence](#9-complete-execution-flow--end-to-end-sequence)
10. [How Your Work Integrates with Members 1–4](#10-how-your-work-integrates-with-members-1-4)
11. [What You Still Need to Build](#11-what-you-still-need-to-build)

---

## 1. Your Role in the Project

The project has five members. Each member is assigned a specific subsystem of the SD Card Health Monitoring Block Driver. Your role, **Member 5**, is the **Automation and Testing Lead**.

Your responsibilities are:

| Responsibility | Formal Definition |
|---|---|
| **Build Automation** | Create and maintain a `Makefile` that compiles all source code produced by Members 1–4 into executable binaries without manual intervention. |
| **Deployment Automation** | Create shell scripts that load the compiled kernel module into the Linux kernel, configure the system for user access, and launch the user-space application — all via a single command. |
| **Cleanup Automation** | Create shell scripts that reverse the deployment: terminate running processes, unload kernel modules, and delete build artifacts. |
| **Test Strategy Design** | Document formal methodologies for verifying that the kernel module is correct under concurrency (race conditions), extreme input values (boundary value analysis), and prolonged operation (memory leak detection). |
| **Test Implementation** | Write executable test scripts that apply the methodologies documented in the test strategy. |
| **Integration Assurance** | Ensure that all automation scripts and tests are compatible with the source code produced by Members 1–4, regardless of when or in what order their branches are merged. |

---

## 2. Key Terminology — Formal Definitions

Before reading the rest of this document, you must understand the following terms. Each term is presented with its formal definition followed by a brief explanation of why it matters to your project.

### 2.1 Loadable Kernel Module (LKM)

**Formal Definition:** A Loadable Kernel Module is a compiled object file (extension `.ko`) containing code that can be dynamically inserted into or removed from a running Linux kernel at runtime, without requiring a system reboot. The kernel treats an LKM as an extension of its own address space — LKM code executes with full kernel privileges (ring 0 on x86 architectures, EL1 on ARM64).

**Relevance to your project:** The file `sdhealth.ko` (produced by your `Makefile`) is the LKM. When loaded, it creates the character device `/dev/sdhealth` and begins monitoring SD card read/write statistics by reading from the sysfs file `/sys/block/mmcblk0/stat`.

### 2.2 Character Device (`/dev/sdhealth`)

**Formal Definition:** A character device is a special file in the Linux filesystem that represents a hardware or virtual device that transfers data as a stream of bytes (one character at a time), as opposed to a block device which transfers data in fixed-size blocks. Character devices are identified by a **major number** (which driver handles them) and a **minor number** (which specific device instance).

**Relevance to your project:** The kernel module registers a character device at `/dev/sdhealth`. User-space programs open this file, send commands via the `write()` system call, and receive statistics via the `read()` system call.

### 2.3 System Calls — `open()`, `read()`, `write()`, `close()`

**Formal Definition:** System calls are controlled entry points from user space into the Linux kernel. When a user-space program invokes `open()`, `read()`, `write()`, or `close()`, the CPU executes a software interrupt (or the `SVC` instruction on ARM64) which transitions the processor from unprivileged user mode (EL0) to privileged kernel mode (EL1). The kernel then routes the call to the appropriate device driver's `file_operations` handler.

**Relevance to your project:** Your `monitor.c` program uses these four system calls to communicate with the kernel module. The module's `fops` structure maps each system call to a handler function (e.g., `open` → `sdhealth_open`).

### 2.4 `insmod` (Insert Module)

**Formal Definition:** `insmod` is a Linux administrative command that loads a `.ko` file into kernel memory. It resolves symbol references, calls the module's initialization function (designated by `module_init()`), and links the module into the kernel's linked list of loaded modules.

**Relevance to your project:** Your `run.sh` script calls `sudo insmod sdhealth.ko` to activate the monitoring driver.

### 2.5 `rmmod` (Remove Module)

**Formal Definition:** `rmmod` is a Linux administrative command that unloads a kernel module. It checks that the module's reference count is zero (no process is using the device), calls the module's exit function (designated by `module_exit()`), and frees all kernel memory allocated by the module.

**Relevance to your project:** Your `cleanup.sh` script calls `sudo rmmod sdhealth` to deactivate the driver and release its resources.

### 2.6 `chmod` (Change Mode — File Permissions)

**Formal Definition:** `chmod` modifies the permission bits of a file or device node. The permission model uses three triples of bits: read (`r` = 4), write (`w` = 2), and execute (`x` = 1) for the **owner**, **group**, and **others** respectively. The value `666` sets read+write for owner, group, and others (`4+2=6` for each).

**Relevance to your project:** By default, `/dev/sdhealth` is created with permissions that only allow the root user to read and write. Your `run.sh` applies `chmod 666` so that the user-space `monitor` program (running as a normal user) can access the device without requiring `sudo` for every read/write operation.

### 2.7 `make` and `Makefile`

**Formal Definition:** `make` is a build automation tool that reads a `Makefile` to determine which source files need to be compiled into which targets. It uses a directed acyclic graph (DAG) of dependencies: if a target file is older than any of its prerequisite files (determined by filesystem timestamps), `make` executes the associated recipe (shell commands) to rebuild the target.

**Relevance to your project:** Your `Makefile` defines two targets: the kernel module (`sdhealth.ko`) and the user-space binary (`monitor`). It also detects which source files exist so it can adapt to either the single-file or multi-file source layout.

### 2.8 Kernel Build System (`/lib/modules/$(uname -r)/build`)

**Formal Definition:** The Linux kernel build system (Kbuild) is a set of Makefiles distributed with the kernel source or kernel headers package. When you run `make -C /lib/modules/$(uname -r)/build M=$(PWD) modules`, the `-C` flag changes to the kernel build directory, and `M=$(PWD)` tells Kbuild to look in your current directory for an external module `Makefile`. Kbuild then compiles your `.c` files against the exact kernel headers of the running kernel, ensuring ABI (Application Binary Interface) compatibility.

**Relevance to your project:** Your `Makefile` delegates kernel module compilation to Kbuild. This is essential because kernel modules must be compiled against the same kernel version, configuration, and architecture as the kernel they will be loaded into.

---

## 3. Files You Created on This Branch

The `automation-testing` branch contains the following files that you authored or modified:

| File | Type | Authorship | Purpose |
|---|---|---|---|
| `Makefile` | Build configuration | **Modified by you** (was a skeleton) | Compiles the kernel module and user-space program |
| `run.sh` | Bash shell script | **Created by you** | Automates build → load → permission → execute |
| `cleanup.sh` | Bash shell script | **Created by you** | Automates kill → unload → clean |
| `monitor.c` | C source (skeleton) | **Created by you** | Minimal user-space program for pipeline testing |
| `TEST_STRATEGIES.md` | Documentation | **Created by you** | Formal test methodology planning document |

Each of these files is explained in detail in the sections below.

---

## 4. The `Makefile` — Line-by-Line Explanation

The `Makefile` is the first file executed in the pipeline. It is read by the `make` program. We will examine it in logical sections.

### 4.1 Source Detection Logic

```makefile
SDHEALTH_MAIN := $(wildcard sdhealth_main.c)
DETECTION_C   := $(wildcard detection.c)
SINGLE_SRC    := $(wildcard sdhealth.c)
```

**Line-by-line explanation:**

- **Line 1:** `SDHEALTH_MAIN := $(wildcard sdhealth_main.c)`  
  The `:=` operator means "assign this value immediately" (not lazily). The `$(wildcard pattern)` function searches the current directory for files matching the pattern. If `sdhealth_main.c` exists, the variable `SDHEALTH_MAIN` is set to the string `sdhealth_main.c`. If the file does not exist, the variable is set to an empty string.

- **Line 2:** `DETECTION_C := $(wildcard detection.c)`  
  Same logic: check whether `detection.c` exists.

- **Line 3:** `SINGLE_SRC := $(wildcard sdhealth.c)`  
  Same logic: check whether `sdhealth.c` exists.

After these three lines execute, exactly one of two conditions will be true:

| Condition | Meaning |
|---|---|
| `SDHEALTH_MAIN` is non-empty AND `DETECTION_C` is non-empty | The multi-file source layout exists (Members 2 & 3's work has been merged) |
| `SINGLE_SRC` is non-empty | Only the single-file layout exists (current `main` branch state) |

### 4.2 Conditional Build Configuration

```makefile
ifneq ($(SDHEALTH_MAIN)$(DETECTION_C),)
  obj-m           += sdhealth.o
  sdhealth-objs   := sdhealth_main.o detection.o
else ifneq ($(SINGLE_SRC),)
  obj-m           += sdhealth.o
else
  $(error No kernel source found in $(MY_SRC_DIR). Expected sdhealth_main.c+detection.c or sdhealth.c)
endif
```

**Line-by-line explanation:**

- **Line 1:** `ifneq ($(SDHEALTH_MAIN)$(DETECTION_C),)`  
  `ifneq (A, B)` means "if A is not equal to B". Here, A is the concatenation of `SDHEALTH_MAIN` and `DETECTION_C`, and B is an empty string. If both files exist, the concatenation is non-empty, so the condition is true. The first branch executes.

- **Lines 2–3 (Multi-file branch):**  
  ```makefile
  obj-m           += sdhealth.o
  sdhealth-objs   := sdhealth_main.o detection.o
  ```
  `obj-m` is a Kbuild variable meaning "this is a loadable module target". `sdhealth-objs` tells Kbuild: "the module `sdhealth.ko` is composed of these object files, which must be linked together." This means Kbuild will first compile `sdhealth_main.c` → `sdhealth_main.o` and `detection.c` → `detection.o`, then link them into `sdhealth.ko`.

- **Lines 4–5 (Single-file branch):**  
  ```makefile
  else ifneq ($(SINGLE_SRC),)
    obj-m           += sdhealth.o
  ```
  If the multi-file sources are absent but `sdhealth.c` exists, set only `obj-m`. Since no `sdhealth-objs` is specified, Kbuild defaults to compiling the single file `sdhealth.c` → `sdhealth.o` → `sdhealth.ko`.

- **Lines 6–8 (Error branch):**  
  ```makefile
  else
    $(error ...)
  ```
  `$(error message)` is a GNU Make function that immediately halts execution and prints the message. This prevents the build from silently producing nothing when source files are missing.

### 4.3 User-Space Binary Target

```makefile
USER_BIN     := monitor
USER_SRC     := monitor.c

$(USER_BIN): $(USER_SRC)
	gcc -Wall -Wextra -O2 -o $@ $<
```

**Line-by-line explanation:**

- **Lines 1–2:** Variable assignments for clarity. `USER_BIN` holds the name of the output binary (`monitor`). `USER_SRC` holds the source file (`monitor.c`).

- **Line 3:** `$(USER_BIN): $(USER_SRC)`  
  This is a **target-prerequisite** declaration. It states: "The file `monitor` depends on the file `monitor.c`." If `monitor` does not exist, or if `monitor.c` is newer than `monitor` (based on filesystem modification timestamps), `make` will execute the recipe on the next line.

- **Line 4:** `gcc -Wall -Wextra -O2 -o $@ $<`  
  - `gcc`: The GNU C Compiler.
  - `-Wall`: Enable all common compiler warnings.
  - `-Wextra`: Enable additional warnings beyond `-Wall`.
  - `-O2`: Apply level-2 optimization (produce efficient machine code without excessive compilation time).
  - `-o $@`: `$@` is an automatic variable that expands to the target name (`monitor`).
  - `$<`: An automatic variable that expands to the first prerequisite (`monitor.c`).

  The full expanded command is: `gcc -Wall -Wextra -O2 -o monitor monitor.c`

### 4.4 The `all` Target

```makefile
all: $(USER_BIN)
	@echo "[BUILD] Compiling kernel module..."
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
	@echo "[BUILD] Done → sdhealth.ko + $(USER_BIN)"
```

**Line-by-line explanation:**

- **Line 1:** `all: $(USER_BIN)`  
  The `all` target depends on `$(USER_BIN)` (i.e., `monitor`). Before executing the `all` recipe, `make` ensures `monitor` is up-to-date by checking its dependency on `monitor.c`.

- **Line 2:** `@echo "[BUILD] Compiling kernel module..."`  
  The `@` prefix suppresses the echoing of the command itself to stdout. Only the output of `echo` is displayed.

- **Line 3:** `make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules`  
  - `$(shell uname -r)` executes the shell command `uname -r` which returns the running kernel version (e.g., `6.12.75+rpt-rpi-v8`).
  - `-C /lib/modules/6.12.75+rpt-rpi-v8/build` changes directory to the kernel build directory.
  - `M=$(PWD)` tells Kbuild: "The external module source is in `$(PWD)`" (the current directory).
  - `modules` is the Kbuild target that compiles all modules listed in `obj-m`.

### 4.5 The `clean` Target

```makefile
clean:
	@echo "[CLEAN] Removing kernel build artifacts..."
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean 2>/dev/null || true
	@echo "[CLEAN] Removing user-space binary..."
	rm -f $(USER_BIN)
	rm -f *.o *.mod *.mod.c *.mod.o .*.cmd .*.d Module.symvers modules.order
```

**Line-by-line explanation:**

- **Line 1:** `clean:` — A phony target (declared `.PHONY: clean` elsewhere). No prerequisites; always executes when requested.

- **Line 3:** `make -C ... clean 2>/dev/null || true`  
  - Invokes Kbuild's own `clean` target to remove kernel build artifacts.
  - `2>/dev/null` redirects standard error to `/dev/null` (suppresses error messages if the build directory is missing).
  - `|| true` ensures the command never returns a failure exit code (prevents the script from stopping if there is nothing to clean).

- **Lines 5–6:** Remove all generated files:
  - `$(USER_BIN)` → the `monitor` binary.
  - `*.o` → compiled object files.
  - `*.mod *.mod.c *.mod.o` → kernel module metadata files.
  - `.*.cmd .*.d` → hidden dependency tracking files.
  - `Module.symvers` → kernel symbol version table.
  - `modules.order` → module load order file.

### 4.6 The `$(MY_SRC_DIR)` Variable

```makefile
MY_SRC_DIR := $(if $(src),$(src),$(CURDIR))
```

**Explanation:**

- `$(if condition, then, else)` is a GNU Make conditional function.
- `$(src)` is a variable set by the **kernel build system** (Kbuild) when it invokes the external module Makefile. It contains the absolute path to the directory containing your Makefile.
- `$(CURDIR)` is a GNU Make built-in variable containing the current working directory of the `make` process.
- **Logic:** If `$(src)` is defined (meaning Kbuild is running this Makefile), use `$(src)`. Otherwise (meaning you ran `make` directly from the command line), use `$(CURDIR)`.

This variable is used in the `$(wildcard ...)` calls to ensure file detection works regardless of whether Kbuild or a direct `make` invocation is processing the Makefile.

---

## 5. The `run.sh` Script — Step-by-Step Execution Trace

The `run.sh` script is a Bash shell script. The first line `#!/bin/bash` tells the operating system to execute this file using the Bash interpreter.

### 5.1 Initialization

```bash
set -euo pipefail
```

**Explanation of each flag:**

| Flag | Full Name | Effect |
|---|---|---|
| `-e` | errexit | If any command exits with a non-zero status code (indicating failure), the script immediately terminates. This prevents a failed build from proceeding to module insertion. |
| `-u` | nounset | If any variable is referenced without having been assigned a value, the script immediately terminates. This catches typographical errors in variable names. |
| `-o pipefail` | pipefail option | In a pipeline (`cmd1 | cmd2`), the exit status is the status of the last (rightmost) command that failed, rather than only the last command. Without this, `false | true` would be considered successful. |

Combined, these three settings make the script **fail-fast**: any unexpected condition causes immediate termination rather than silent continuation with incorrect state.

### 5.2 Step 1 — Build

```bash
echo_info "Step 1/4 — Building kernel module and user-space monitor..."
if make; then
    echo_info "Build completed successfully."
else
    echo_error "Build failed — check compiler errors above."
    exit 1
fi
```

**Execution trace:**

| Step | What happens | Possible states |
|---|---|---|
| 1 | `echo_info` prints a green `[INFO]` line to the terminal | — |
| 2 | `make` is executed as a child process | — |
| 3a | `make` returns exit code 0 | The `if` condition is true. `echo_info` prints success. |
| 3b | `make` returns exit code non-zero | The `if` condition is false. `echo_error` prints a red `[ERROR]` line. `exit 1` terminates the script with status 1. |

After this step, the following files exist in the current directory: `sdhealth.ko` (kernel module), `monitor` (user-space binary), and several intermediate build artifacts (`*.o`, `*.mod.c`, etc.).

### 5.3 Step 2 — Insert Kernel Module

```bash
echo_info "Step 2/4 — Inserting sdhealth.ko into the kernel..."
if lsmod | grep -q "^sdhealth"; then
    echo_warn "sdhealth module is already loaded — removing it first."
    sudo rmmod sdhealth
fi
sudo insmod sdhealth.ko
echo_info "Module loaded.  Verify:  lsmod | grep sdhealth"
```

**Execution trace:**

| Step | Command | What happens |
|---|---|---|
| 1 | `lsmod` | Lists all currently loaded kernel modules. |
| 2 | `grep -q "^sdhealth"` | Searches the output of `lsmod` for a line beginning with `sdhealth`. The `-q` flag means "quiet" — suppress output, only return exit status. The `^` is a regex anchor matching the start of a line. |
| 3a | grep finds a match (exit 0) | The `if` condition is true. The script prints a warning and removes the existing module with `sudo rmmod sdhealth`. This handles the case where a previous `run.sh` was not properly cleaned up. |
| 3b | grep finds no match (exit 1) | The `if` condition is false. The script skips the `rmmod` and proceeds to insertion. |
| 4 | `sudo insmod sdhealth.ko` | Loads the kernel module. At this point: the `sdhealth_init()` function executes inside the kernel, `alloc_chrdev_region()` allocates a major number, `cdev_add()` registers the character device, `class_create()` and `device_create()` create `/dev/sdhealth`, and `timer_setup()` + `mod_timer()` start the statistics timer. |
| 5 | `echo_info` | Prints a confirmation message with a suggested verification command. |

### 5.4 Step 3 — Set Device Permissions

```bash
echo_info "Step 3/4 — Setting permissions on /dev/sdhealth..."
if [ -e /dev/sdhealth ]; then
    sudo chmod 666 /dev/sdhealth
    echo_info "Permissions set: $(ls -l /dev/sdhealth)"
else
    echo_error "/dev/sdhealth not found — did the module load correctly?"
    echo_error "Check dmesg:  sudo dmesg | tail -20"
    exit 1
fi
```

**Execution trace:**

| Step | Command | What happens |
|---|---|---|
| 1 | `[ -e /dev/sdhealth ]` | The `[ -e file ]` test returns true if the file (or device node) exists. |
| 2a | File exists | `sudo chmod 666 /dev/sdhealth` changes permissions to `crw-rw-rw-` (readable and writable by owner, group, and others). The `$(ls -l /dev/sdhealth)` command substitution displays the new permissions for verification. |
| 2b | File does not exist | The script prints error messages and terminates with `exit 1`. This indicates the kernel module failed to create the device node — possibly due to an error in `sdhealth_init()`. |

**Why `chmod 666` is necessary:** Kernel device nodes are created with default permissions `crw-------` (only root can read/write). Without changing permissions, the `monitor` program would need `sudo` to open the device. Since the monitor is a user-space program that should run without elevated privileges, permissions must be relaxed. The value `666` (binary `110 110 110`) grants read (bit 2) and write (bit 1) to owner, group, and others, but not execute (bit 0), since device nodes are not executable files.

### 5.5 Step 4 — Launch Monitor

```bash
echo_info "Step 4/4 — Launching user-space monitor..."
echo ""
./monitor
```

**Execution trace:**

| Step | What happens |
|---|---|
| 1 | `./monitor` is executed as a child process. The `./` prefix tells the shell to look for the executable in the current directory (as opposed to searching `$PATH`). |
| 2 | Inside `monitor` (see Section 7 for full walkthrough): `open("/dev/sdhealth")` → `write(fd, "REQUEST_STATS")` → `read(fd, buffer)` → `printf(buffer)` → `close(fd)`. |
| 3 | `monitor` exits. Control returns to `run.sh`. |
| 4 | The script prints a final message directing the user to use `cleanup.sh`. |

---

## 6. The `cleanup.sh` Script — Step-by-Step Execution Trace

`cleanup.sh` performs the inverse of `run.sh`. It is idempotent — running it multiple times produces the same result without errors.

### 6.1 Step 1 — Terminate User-Space Monitor

```bash
if pgrep -f "./monitor" > /dev/null 2>&1; then
    pkill -f "./monitor"
elif pgrep -f "monitor" > /dev/null 2>&1; then
    pkill -f "monitor"
else
    echo_info "No monitor process found — nothing to kill."
fi
```

**Execution trace:**

| Step | Command | What happens |
|---|---|---|
| 1 | `pgrep -f "./monitor"` | Searches the process table for any process whose full command line contains the substring `./monitor`. |
| 2a | Match found | `pkill -f "./monitor"` sends `SIGTERM` (signal 15) to all matching processes, requesting graceful termination. |
| 2b | No match | The `elif` branch searches for any process whose command line contains `monitor` (broader pattern, catches the program regardless of how it was invoked). |
| 2c | Neither pattern matches | The `else` branch prints that no monitor is running — this is a normal, non-error state. |

### 6.2 Step 2 — Remove Kernel Module

```bash
if lsmod | grep -q "^sdhealth"; then
    sudo rmmod sdhealth
else
    echo_info "sdhealth module is not loaded — nothing to remove."
fi
```

**Execution trace:**

| Step | What happens |
|---|---|
| 1 | `lsmod | grep -q "^sdhealth"` checks if the module is loaded. |
| 2a | If loaded: `sudo rmmod sdhealth` triggers `sdhealth_exit()`, which calls `del_timer_sync()` (cancel timer), `device_destroy()` (remove `/dev/sdhealth`), `class_destroy()`, `cdev_del()`, and `unregister_chrdev_region()` (release major number). All kernel memory allocated by the module is freed. |
| 2b | If not loaded: print a message and continue. |

### 6.3 Step 3 — Clean Build Artifacts

```bash
make clean 2>/dev/null || true
echo_info "Cleanup complete."
```

**Execution trace:**

| Step | What happens |
|---|---|
| 1 | `make clean` invokes the `clean` target in the `Makefile`, which removes `sdhealth.ko`, `monitor`, all `.o` files, and all intermediate build artifacts. |
| 2 | `2>/dev/null` suppresses any error output. `|| true` ensures the command returns success even if there is nothing to clean. |
| 3 | After this step, the directory contains only source files — identical to the state before `run.sh` was executed. |

---

## 7. The `monitor.c` Skeleton — Code Walkthrough

This is a **skeleton** user-space C program. Its purpose is to validate the automation pipeline (Makefile → insmod → read/write → rmmod). It is not the final interactive monitor — that will be provided by Member 3 on the `kernel-user-comms` branch.

### 7.1 Header Files

```c
#include <stdio.h>      // Standard I/O: printf, perror, fprintf, stderr
#include <stdlib.h>     // Standard library: EXIT_SUCCESS, EXIT_FAILURE
#include <fcntl.h>      // File control: open(), O_RDWR
#include <unistd.h>     // UNIX standard: read(), write(), close()
#include <string.h>     // String operations: strlen()
```

Each `#include` directive tells the C preprocessor to copy the contents of the specified header file into this source file before compilation. These five headers provide the declarations for all functions used in the program.

### 7.2 Constants

```c
#define DEVICE_PATH     "/dev/sdhealth"
#define BUFFER_SIZE      4096
#define CMD_REQUEST      "REQUEST_STATS"
```

| Constant | Value | Purpose |
|---|---|---|
| `DEVICE_PATH` | `"/dev/sdhealth"` | The filesystem path to the character device created by the kernel module. Used as the first argument to `open()`. |
| `BUFFER_SIZE` | `4096` | The size in bytes of the read buffer. 4096 bytes (4 KiB) is one memory page on ARM64 — a standard unit of memory allocation. |
| `CMD_REQUEST` | `"REQUEST_STATS"` | The command string sent to the kernel module via `write()`. The kernel module's `sdhealth_write()` function receives this string and logs it with `printk`. |

### 7.3 Main Function — Full Execution Trace

```c
int main(void)
{
    int  fd;
    char buffer[BUFFER_SIZE];
    int  bytes_written;
    int  bytes_read;
```

**Step 1 — Variable declarations:** The compiler allocates stack space for:
- `fd`: a file descriptor (integer). Value is uninitialized at this point.
- `buffer`: an array of 4096 `char` elements on the stack. All elements contain undefined values.
- `bytes_written`: an integer. Uninitialized.
- `bytes_read`: an integer. Uninitialized.

---

```c
    fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0)
    {
        perror("[monitor] ERROR: Cannot open " DEVICE_PATH);
        fprintf(stderr,
                "[monitor] HINT: Is the kernel module loaded?\n"
                "[monitor] Try:  sudo insmod sdhealth.ko\n");
        return EXIT_FAILURE;
    }
```

**Step 2 — Open the device:**

| Sub-step | What happens |
|---|---|
| 2.1 | `open("/dev/sdhealth", O_RDWR)` executes. The CPU transitions from user mode (EL0) to kernel mode (EL1) via the `open` system call. |
| 2.2 | The kernel's Virtual File System (VFS) layer locates the inode for `/dev/sdhealth`, identifies it as a character device with the major number assigned to `sdhealth`, and calls `sdhealth_open()` in the kernel module. |
| 2.3 | `sdhealth_open()` prints `[SDHEALTH] Device opened` to the kernel log and returns 0. |
| 2.4 | The kernel allocates a file descriptor (the lowest available non-negative integer not currently in use by this process) and returns it to user space. |
| 2.5a | If `fd >= 0`: the `if` condition is false. Execution continues to Step 3. |
| 2.5b | If `fd < 0` (error): `perror()` prints the error description to stderr. `fprintf()` prints a hint. `return EXIT_FAILURE` terminates the program with exit code 1. |

After Step 2, `fd` holds a valid file descriptor (typically 3, since 0=stdin, 1=stdout, 2=stderr).

---

```c
    bytes_written = write(fd, CMD_REQUEST, strlen(CMD_REQUEST));
    if (bytes_written < 0)
    {
        perror("[monitor] ERROR: write() failed");
        close(fd);
        return EXIT_FAILURE;
    }
```

**Step 3 — Send command to kernel:**

| Sub-step | What happens |
|---|---|
| 3.1 | `strlen(CMD_REQUEST)` evaluates to 13 (the number of characters in `"REQUEST_STATS"`, excluding the null terminator). |
| 3.2 | `write(fd, "REQUEST_STATS", 13)` executes. The kernel routes this to `sdhealth_write()` in the kernel module. |
| 3.3 | `sdhealth_write()` copies the 13 bytes from user space to a kernel buffer using `copy_from_user()`, then prints `[SDHEALTH] Received from user space: REQUEST_STATS` to the kernel log. |
| 3.4 | The return value (13) is stored in `bytes_written`. |
| 3.5a | If `bytes_written >= 0`: the `if` condition is false. Continue to Step 4. |
| 3.5b | If `bytes_written < 0`: an error occurred. Print error, close the file descriptor (freeing the kernel resources), and exit. |

---

```c
    bytes_read = read(fd, buffer, sizeof(buffer) - 1);
    if (bytes_read < 0)
    {
        perror("[monitor] ERROR: read() failed");
        close(fd);
        return EXIT_FAILURE;
    }

    buffer[bytes_read] = '\0';
```

**Step 4 — Read statistics from kernel:**

| Sub-step | What happens |
|---|---|
| 4.1 | `sizeof(buffer) - 1` evaluates to 4095 (the buffer size minus one byte reserved for null termination). |
| 4.2 | `read(fd, buffer, 4095)` executes. The kernel routes this to `sdhealth_read()`. |
| 4.3 | Inside `sdhealth_read()`: `update_stats()` is called, which opens `/sys/block/mmcblk0/stat`, reads the raw statistics, parses them with `sscanf()`, and updates the global counters (`READ_count`, `WRITE_count`, etc.). Then `snprintf()` formats a human-readable string, and `copy_to_user()` copies it into the `buffer` in user space. |
| 4.4 | `bytes_read` receives the number of bytes actually copied (the length of the formatted statistics string). |
| 4.5a | If `bytes_read >= 0`: continue. |
| 4.5b | If `bytes_read < 0`: error handling as in Step 3. |
| 4.6 | `buffer[bytes_read] = '\0'` places a null terminator at position `bytes_read` in the buffer. This converts the raw byte array into a valid C string suitable for `printf()`. |

After Step 4, `buffer` contains a null-terminated string like:
```
SD Health Monitor
Reads: 9204
Writes: 1127
Read rate: 0/sec
Write rate: 0/sec
Read throughput: 0 KB/s
Write throughput: 0 KB/s
Read sectors: 893759
Write sectors: 547955
```

---

```c
    printf("\n============================================\n");
    printf("  SD Card Health Monitor — Statistics\n");
    printf("============================================\n");
    printf("%s", buffer);
    printf("============================================\n");

    close(fd);
    return EXIT_SUCCESS;
}
```

**Step 5 — Display and cleanup:**

| Sub-step | What happens |
|---|---|
| 5.1 | Three `printf()` calls print a formatted header to stdout. |
| 5.2 | `printf("%s", buffer)` prints the statistics string obtained from the kernel module. |
| 5.3 | A footer line is printed. |
| 5.4 | `close(fd)` executes the `close` system call. The kernel calls `sdhealth_release()`, which prints `[SDHEALTH] Device closed` to the kernel log and returns 0. The file descriptor is freed. |
| 5.5 | `return EXIT_SUCCESS` (which equals 0) terminates the program, indicating success to the shell. |

---

## 8. The `TEST_STRATEGIES.md` Document — Future Planning

The `TEST_STRATEGIES.md` file is a **planning document**, not executable code. It defines what tests you will implement in the future, organized into three categories:

### 8.1 Race Condition Testing

**What it tests:** Whether the kernel module behaves correctly when multiple processes access `/dev/sdhealth` simultaneously. Since the module's `update_stats()` function modifies global `static` variables without any locking mechanism (no `mutex`, no `spinlock`), concurrent access could produce incorrect results.

**Why it matters:** If two processes read at the same time, one could see partially-updated counters (a "torn read"). If a user-space `read()` and the kernel timer callback both execute `update_stats()` simultaneously, the `initial_reading` flag could be corrupted.

**Tests proposed:** Parallel reader bombardment, reader-writer interleaving, timer-vs-user race, open/close flood, KCSAN.

### 8.2 Boundary Value Analysis

**What it tests:** Whether the anomaly detection subsystem correctly identifies when write or read counts cross defined thresholds (WRITE_THRESHOLD = 1000, READ_THRESHOLD = 5000).

**Why it matters:** The detection system uses a one-shot guard (`write_alert_sent` flag) to prevent log spam. This guard must correctly reset when the rate drops below threshold and re-trigger when it rises again. Incorrect behavior would mean either missing warnings (false negatives) or excessive log messages (false positives).

**Tests proposed:** Threshold just-below/at/just-above, sustained above-threshold, rapid threshold oscillation, throughput saturation, zero-length I/O.

### 8.3 Dynamic Memory Analysis

**What it tests:** Whether the kernel module leaks memory. A kernel memory leak is a block of allocated memory that is never freed. Since the kernel has no garbage collector, leaked memory is permanently lost until the system is rebooted.

**Why it matters:** If `sdhealth_init()` allocates resources and `sdhealth_exit()` does not free them all, each load/unload cycle permanently consumes a small amount of kernel memory. Over many cycles (or over long uptime), this degrades system performance and may eventually cause allocation failures.

**Tests proposed:** Load/unload cycle test with `/proc/meminfo` comparison, kmemleak scanning, slab allocator inspection, open/close leak check, timer teardown verification, static analysis with Sparse.

### 8.4 Integration & Regression Test Pipeline (Section 4 of TEST_STRATEGIES.md)

This section defines the **future** `test_suite.sh` master script. The proposed flow is:

1. Execute `run.sh` for setup (build + load + permissions).
2. Execute each test category sequentially.
3. Capture `dmesg` output after each test for evidence.
4. Produce a colored pass/fail summary.
5. Execute `cleanup.sh` for teardown, even if tests fail (using a `trap` handler to ensure cleanup runs on script exit).

### 8.5 Notes for Fellow Team Members (Section 5 of TEST_STRATEGIES.md)

This section lists what each member must provide for your tests to work:

| Member | Deliverable | Why You Need It |
|---|---|---|
| 1 | Consistent `printk` tags (`[SDHEALTH]`) | Your test scripts use `dmesg | grep '\[SDHEALTH\]'` to verify kernel behavior. Inconsistent tags break this. |
| 2 | `#define` thresholds in `detection.h` | Your boundary value tests need to know the exact numeric thresholds to generate test inputs. |
| 3 | `--once` flag on `monitor.c` | Your automated tests cannot use an interactive menu. A non-interactive mode lets scripts invoke the monitor programmatically. |
| 4 | Consistent `read()` output format | Your test scripts parse the statistics string. A change in format (e.g., different field order) breaks parsing. |

---

## 9. Complete Execution Flow — End-to-End Sequence

The following is the complete sequence of events when a user runs `./run.sh` followed by `./cleanup.sh` on the Raspberry Pi.

### 9.1 `./run.sh` Execution Sequence

```
Step 1: make
  ├── gcc -Wall -Wextra -O2 -o monitor monitor.c
  │     Produces: monitor (user-space executable)
  └── make -C /lib/modules/6.12.75+rpt-rpi-v8/build M=... modules
        ├── CC sdhealth.o          (compiles sdhealth.c)
        ├── MODPOST Module.symvers (generates symbol table)
        └── LD sdhealth.ko        (links into kernel object)
              Produces: sdhealth.ko

Step 2: sudo insmod sdhealth.ko
  └── Kernel executes sdhealth_init():
        ├── alloc_chrdev_region()      → allocates major number (e.g., 236)
        ├── cdev_init() + cdev_add()   → registers character device
        ├── class_create()              → creates /sys/class/sdhealth_class
        ├── device_create()             → creates /dev/sdhealth
        └── timer_setup() + mod_timer() → starts periodic statistics timer

Step 3: sudo chmod 666 /dev/sdhealth
  └── Permissions changed to crw-rw-rw-

Step 4: ./monitor
  ├── open("/dev/sdhealth")    → kernel calls sdhealth_open()
  ├── write(fd, "REQUEST_STATS") → kernel calls sdhealth_write()
  ├── read(fd, buffer, 4095)   → kernel calls sdhealth_read()
  │     └── sdhealth_read() internally:
  │           ├── update_stats()
  │           │     ├── filp_open("/sys/block/mmcblk0/stat")
  │           │     ├── kernel_read()      → reads raw stats
  │           │     ├── sscanf()            → parses counters
  │           │     └── filp_close()
  │           └── snprintf() + copy_to_user() → returns formatted string
  ├── printf()                  → displays stats to terminal
  └── close(fd)                → kernel calls sdhealth_release()
```

### 9.2 `./cleanup.sh` Execution Sequence

```
Step 1: pkill -f monitor
  └── Sends SIGTERM to any running monitor process (if any)

Step 2: sudo rmmod sdhealth
  └── Kernel executes sdhealth_exit():
        ├── del_timer_sync()           → cancels and waits for timer
        ├── device_destroy()            → removes /dev/sdhealth
        ├── class_destroy()             → removes /sys/class/sdhealth_class
        ├── cdev_del()                  → unregisters character device
        └── unregister_chrdev_region()  → releases major number 236

Step 3: make clean
  ├── Kbuild clean → removes *.o, *.ko, Module.symvers, modules.order
  └── rm monitor   → removes user-space binary
```

After both scripts complete, the filesystem is in its original state: only source code files remain. No kernel resources are consumed.

---

## 10. How Your Work Integrates with Members 1–4

Your automation framework is designed to be **merge-order independent**. This means it works correctly regardless of whether Members 1–4 merge their branches before or after you merge yours.

### 10.1 Source File Detection

Your `Makefile` detects which source files exist at build time:

```
Does sdhealth_main.c + detection.c exist?
  ├── YES → Build sdhealth.ko from sdhealth_main.o + detection.o
  └── NO  → Does sdhealth.c exist?
              ├── YES → Build sdhealth.ko from sdhealth.o
              └── NO  → Error: stop build
```

This means:
- If only `main` branch code is present (`sdhealth.c` only): Build works.
- If Members 2 & 3 have merged (`sdhealth_main.c` + `detection.c`): Build works.
- If no source files exist: Build fails with a clear error message.

### 10.2 Device Path Consistency

All your scripts and programs use the device path `/dev/sdhealth`. This is the name defined by `#define DEVICE_NAME "sdhealth"` in both `sdhealth.c` (current main) and `sdhealth_main.c` (detection-logging branch). The name is consistent across all branches.

### 10.3 Write Command Compatibility

Your `monitor.c` skeleton sends the command `"REQUEST_STATS"` via `write()`. Looking at the kernel module's `sdhealth_write()` function on all branches, it simply logs whatever string it receives — it does not parse or validate the command. Therefore, any command string is compatible.

### 10.4 Read Output Parsing

Your skeleton `monitor.c` prints the raw statistics string to stdout without parsing it. This means it works with any output format. Future test scripts will need to parse specific fields (e.g., to extract `Writes: N` and compare against a threshold). This parsing depends on a stable output format, which is why `TEST_STRATEGIES.md` Section 5 asks Member 4 to maintain a consistent format.

---

## 11. What You Still Need to Build

Your current branch provides the **foundational automation framework**. The following items remain to be implemented:

### 11.1 Immediate Priority — Load/Unload Cycle Test

Create `test_memory_leak.sh`:
```bash
#!/bin/bash
# Records free memory before and after N load/unload cycles
# Flags any decrease as a potential kernel memory leak
```

This test can be written and executed **today** because it only depends on the kernel module (which already exists on `main` and compiles). It does not require any code from Members 2–4.

### 11.2 After Merge — Race Condition Tests

Create `test_race_conditions.sh` and a companion C program `race_reader.c` that spawns multiple processes performing concurrent reads from `/dev/sdhealth`. This requires the kernel module to be stable (Member 1) and for your test harness to handle process synchronization.

### 11.3 After Merge — Boundary Value Tests

Create `test_boundary_values.sh` that uses `dd` to generate precise write counts and checks `dmesg` for threshold warnings. This requires the detection subsystem (Member 2) to be merged so that the `check_anomaly()` function and the `WRITE_THRESHOLD` / `READ_THRESHOLD` constants exist.

### 11.4 After All Merges — Master Test Suite

Create `test_suite.sh` that sequentially invokes `run.sh`, all test scripts, and `cleanup.sh`, producing a single pass/fail report. This is the final deliverable for your role.

---

## Summary — What to Remember

1. **Your branch is `automation-testing`.** It contains five files: `Makefile` (modified), `run.sh`, `cleanup.sh`, `monitor.c`, and `TEST_STRATEGIES.md`.

2. **`./run.sh`** builds everything, loads the kernel module, sets device permissions, and runs the monitor. It is a single command that replaces four manual steps.

3. **`./cleanup.sh`** reverses everything: kills the monitor, removes the module, deletes binaries. It returns the directory to a clean source-only state.

4. **The `Makefile`** is merge-compatible — it detects whether the source is single-file (`sdhealth.c`) or multi-file (`sdhealth_main.c` + `detection.c`) and builds accordingly. No manual configuration is needed.

5. **`monitor.c`** is a skeleton. It proves the automation pipeline works. It will be replaced by Member 3's full menu-driven monitor after merge.

6. **`TEST_STRATEGIES.md`** is your test planning document. It defines what you will implement next. The load/unload cycle test is the highest priority because it can be built immediately.

7. **Your work is validated.** The entire pipeline has been tested on the Raspberry Pi (kernel 6.12.75+rpt-rpi-v8, ARM64) and confirmed working end-to-end.

---

*Generated for Member 5 (Faris) — CSC1107 Group 9 — 2026-06-16*
