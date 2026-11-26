# FalconFloat v1.0.0

First tagged release of FalconFloat, the open-source floating-point units for FALCON (FN-DSA) signature generation on FPGA (ICFPT 2026).

The units target FALCON's needs: no NaN, infinity, overflow/underflow or subnormal support. Where FALCON has a reference operation, the unit is bit-exact with it. Every unit has a self-checking testbench and a Python vector generator.

## New units

- **Floor / ceil:** `fpr_ceil`, `fpr_ceil_and_residue`, `fpr_floor_int_fpr_and_residue`, `fpr_ceil_int_fpr_and_residue` (the floor or ceil as int64 and/or FP64, plus the residue).
- **`fpr_trunc`:** truncation to int64.
- **`fpr_to_int`:** floor, ceil, trunc and round in one shared unit, with int64, FP64 and residue outputs.
- **`fpr_fma`:** multiply-add, with fused or FALCON bit-exact unfused rounding, 1 or 2 register stages, and a 2-bit op for the four sign forms.
- **`fpr_mac`:** accumulating multiply-add built on `fpr_fma`.
- **`fpr_butterfly`:** FFT/iFFT butterfly, one per cycle, bit-exact with FALCON's FFT.
- **`fpr_div`, `fpr_inv`, `fpr_sqrt`:** correctly rounded divide, reciprocal and square root, iterative or pipelined, 1–27 bits per step.
- **`fpr_div_sqrt`:** a merged divide/square-root unit (smaller; one operation at a time).
- **`karatsuba_mul`, `comba_mul`:** 64x64 multipliers, selectable in `defines.vh` for every unit that multiplies.

## Changes

- **`fpr_top` replaces `fpr_top_full` and `fpr_top_partial`:** one configurable wrapper whose parameters choose the units.
  - Fixes output selection: before, issuing a different op on the next cycle could route a result to the wrong output.
  - Results from units with different latencies no longer collide; each result is tagged with its op and a user tag.
  - Unsupported ops return an error flag instead of hanging.
  - It is a convenience wrapper, not tuned for a particular FALCON implementation; pick the individual modules for a real design.
- **Standalone multiplier option:** `fpr_mul`, `fpr_fma` and `fpr_mac` take `INTERNAL_MULT = 1` to use their own multiplier instead of the shared one.
- **128-bit multiply:** `fpr_mul_top` returns the full unsigned 64x64 → 128-bit product (`fpr_mul_op = 2'b10`).
- **Docs:** new `HOW_TO_USE_README.md` (tool setup, generators, testbenches, module parameters); citation placeholder in `README.md`.

## Compatibility

- Existing `fpr_mul_top` users are unaffected: the 1-bit `fpr_mul_op` still works, and the default `INTERNAL_MULT = 0` keeps the shared-multiplier ports as before.
- Designs that used `fpr_top_full` or `fpr_top_partial` need to move to `fpr_top`.
