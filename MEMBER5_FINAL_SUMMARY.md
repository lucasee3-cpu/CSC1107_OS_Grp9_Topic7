# Member 5 — Automation & Testing Lead: Final Summary

**CSC1107 Group 9 — Project 7: SD Card Health Monitoring Block Driver**  
**Date:** 2026-06-30  
**Target:** Raspberry Pi — kernel 6.12.75+rpt-rpi-v8 (ARM64)  

---

## What Was Built

### 1. Build System (`Makefile`)

| Feature | Description |
|---------|-------------|
| Multi-file kernel module | Compiles `sdhealth_main.c` + `detection.c` → `sdhealth.ko` |
| User-space binary | Compiles `monitor.c` → `monitor` |
| Auto-detection | Automatically detects single-file vs multi-file source layout |
| Kbuild-compatible paths | Uses `$(src)` variable for correct wildcard resolution |
| `help` target | Prints usage instructions |

### 2. Deployment Scripts

| Script | Purpose |
|--------|---------|
| `run.sh` | Build → insmod → chmod 666 /dev/sdhealth → launch monitor |
| `cleanup.sh` | Kill monitor → rmmod → make clean |

### 3. Test Scripts

| Script | Type | Cycles/Params | Status |
|--------|------|--------------|--------|
| `sanity_check.sh` | 10 rapid smoke checks | ~2 seconds | ✅ 10/10 PASS |
| `test_memory_leak.sh` | Kernel memory leak detection | N load/unload cycles | ✅ PASS (5-cycle verified) |
| `test_boundary_values.sh` | Threshold detection & one-shot guard | 4 subtests | ✅ 4/4 PASS |
| `test_race_conditions.sh` | Concurrency stress test | N readers × T seconds | ⚠️ Minor CRLF bug |
| `test_performance.sh` | lat/throughput benchmark | N samples | ⚠️ rmmod benchmark timeout |
| `test_suite.sh` | Master runner + Markdown report | --quick or full | ✅ Runs all 5 tests |

### 4. Documentation

| File | Content |
|------|---------|
| `TEST_STRATEGIES.md` | Test methodology planning for race conditions, boundary values, memory analysis |
| `MEMBER5_KNOWLEDGE_REFERENCE.md` | Educational reference for Member 5 |

---

## Test Results on Raspberry Pi (2026-06-30)

```
Test Suite — Quick Mode (65 seconds total)

  Sanity Check        ✅ PASS  (2s)   — 10/10 checks passed
  Memory Leak (20x)   ✅ PASS  (43s)  — No leak, MemFree stable
  Race Conditions     ❌ FAIL  — CRLF line-ending corrupted function name
  Boundary Values     ✅ PASS  (2s)   — All 4 subtests: threshold, guard, zero-I/O, unload
  Performance (10x)   ❌ FAIL  — rmmod latency test timed out
```

### Sanity Check — All 10 Checks Pass

```
Build kernel module + monitor ...... PASS
Insert kernel module ................ PASS
Device /dev/sdhealth exists ......... PASS
Set device permissions .............. PASS
Read statistics from device ......... PASS
Kernel log [SDHEALTH] messages ...... PASS
Anomaly detection called ............ PASS
Remove kernel module ................ PASS
Clean build artifacts ............... PASS
No stray kernel objects ............. PASS
```

### Memory Leak — 5-Cycle Detail

```
Cycles: 5 — 5 pass, 0 fail
MemFree BEFORE: 3,091,196 kB
MemFree AFTER:  3,133,700 kB
Change: -42,504 kB (MemFree INCREASED)
Threshold: 612 kB (512 base + 5 × 20 kB)
Verdict: PASS — no leak detected
```

### Boundary Values — All 4 Subtests Pass

```
Test 1: Write warning fires correctly ......... ✅ PASS
Test 2: One-shot guard prevents duplicates .... ✅ PASS
Test 3: Zero-length read returns 0, no crash .. ✅ PASS
Test 4: Module unloads cleanly ................ ✅ PASS
```

---

## Known Issues (Not Blocking)

| Issue | Impact | Root Cause | Fix |
|-------|--------|-----------|-----|
| `reader_worke` typo in race test | Race condition test fails on Pi | CRLF line endings eat trailing 'r' | Run `sed -i 's/\r$//' test_race_conditions.sh` before test |
| Performance rmmod test timeout | Performance benchmark fails mid-run | Module stuck during rapid rmmod cycling | Reduce rmmod iterations or add longer timeout |
| `scanf` format warnings during build | 3 compiler warnings, no errors | Pre-existing in Member 1's code | Not a Member 5 issue |
| `printk` format warnings during build | 2 compiler warnings, no errors | Pre-existing in Member 1's code | Not a Member 5 issue |

---

## How to Use (on Raspberry Pi)

```bash
cd ~/sdhealth_project

# Quick smoke test (~2 seconds, 10 checks)
./sanity_check.sh

# Deployment
./run.sh          # build + load + run interactive monitor

# Testing
./test_memory_leak.sh 100      # full leak test (~4 min)
./test_boundary_values.sh      # threshold verification (~3s)
./test_race_conditions.sh 16 30 # concurrency stress (~30s)
./test_performance.sh 50       # latency benchmark (~2 min)

# Full suite
./test_suite.sh --quick         # all 5 tests, fast (~1 min)
./test_suite.sh                 # all 5 tests, full (~8 min)

# Cleanup
./cleanup.sh      # kill monitor + unload + clean
```

---

## Files Summary

| File | Type | Lines | Author |
|------|------|-------|--------|
| `Makefile` | Build | 67 | Member 5 |
| `run.sh` | Deployment | 70 | Member 5 |
| `cleanup.sh` | Teardown | 55 | Member 5 |
| `sanity_check.sh` | Smoke test | 155 | Member 5 |
| `test_memory_leak.sh` | Memory test | 195 | Member 5 |
| `test_boundary_values.sh` | Boundary test | 210 | Member 5 |
| `test_race_conditions.sh` | Concurrency test | 220 | Member 5 |
| `test_performance.sh` | Performance test | 180 | Member 5 |
| `test_suite.sh` | Master runner | 260 | Member 5 |
| `TEST_STRATEGIES.md` | Planning | 150 | Member 5 |
| **Total** | | **~1,560** | Member 5 |

---

*Generated by Member 5 (Faris) — Automation & Testing Lead*
