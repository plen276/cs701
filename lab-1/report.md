# COMPSYS 701 - Lab 1 Report

**Author:** Pulasthi Lenaduwa  
**UPI:** plen276  

---

## Part 4 — Cache Performance Optimisation

### 4a) Matrix Operations Application

The application performs element-wise or matrix multiplication operations on two NxN matrices of 32-bit integers. The operation is selected via switches SW0:SW1 on the DE1-SoC board:

| SW1 | SW0 | Operation |
|-----|-----|-----------|
| 0 | 0 | Minimum Value |
| 0 | 1 | Addition |
| 1 | 0 | Subtraction |
| 1 | 1 | Multiplication |

The selected operation is displayed on the two left-most seven-segment displays (HEX4, HEX5).

For testing, N = 8 was used with the following initialisation:
- `A[i][j] = i * N + j + 1` (values 1–64)
- `B[i][j] = (i - j) * 3` (values ranging from -21 to +21)
- `C[i][j] = 0` (zeroed)

---

### 4b) Performance Measurement — Baseline (No Cache)

The `alt_timestamp()` high-resolution timer (50 MHz, `high_res_timer`) was used to measure the execution time of `Matrix_Operations` in clock cycles. The overhead of reading the timer was subtracted from each measurement.

**Baseline result (no instruction or data cache), N = 8:**

| Operation | Ticks |
|-----------|--------|
| Minimum Value  | 69,023 |
| Addition       | 65,941 |
| Subtraction    | 69,612 |
| Multiplication | 604,428 |

> Timer frequency: 50,000,000 Hz.

---

### 4c) Design Space Exploration — Cache Size Optimisation

The Nios II processor was configured with various instruction and data cache sizes (up to 16KB each). The `Matrix_Operations` function was timed for each configuration with N = 8 and the **Multiplication** operation (most compute-intensive, best for cache analysis).

**Working set analysis:**
- Matrix data (A, B, C): 3 × 8 × 8 × 4 bytes = **768 bytes**
- `Matrix_Operations` code: ~few hundred bytes

| Config | I-Cache | D-Cache | Cycles | Speedup vs Baseline |
|--------|---------|---------|--------|---------------------|
| Baseline | None | None | 604,428 | 1.00× |
| 1 | 2 KB | 2 KB | 51,019 | 11.85× |
| 2 | 4 KB | 4 KB | 51,101 | 11.83× |
| 3 | 16 KB | 16 KB | 50,948 | 11.86× |

**Optimum configuration:** 2 KB I-Cache / 2 KB D-Cache

**Discussion:**  
The total matrix data footprint is only 768 bytes (3 × 8 × 8 × 4 bytes), and the instruction footprint of `Matrix_Operations` is similarly small. As a result, a 2 KB cache is sufficient to hold the entire working set, yielding an 11.85× speedup over the no-cache baseline. Increasing the cache to 4 KB and 16 KB produces no meaningful improvement (51,101 and 50,948 cycles respectively), confirming that the working set fits entirely within 2 KB. Therefore, **2 KB / 2 KB is the optimum configuration** — the smallest size that achieves near-maximum performance for N = 8.

---
