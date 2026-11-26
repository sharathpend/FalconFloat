# How to use

How to install the tools, generate test vectors, and run the testbenches.

## Repository layout

| Folder         | Contents                                                       |
|----------------|----------------------------------------------------------------|
| `rtl/`         | RTL for the floating-point units (`defines.vh` holds global defines) |
| `scripts/`     | Python test vector generators (`*_gen_vectors.py`)             |
| `sim/`         | Self-checking testbenches (`*_tb.sv`) and test vectors (`*_vectors.hex`) |
| `constraints/` | Timing constraints for FPGA implementation                     |

## 1. Install the tools

You need:

- **Python 3** (standard library only, no extra packages)
- **Icarus Verilog** (`iverilog` and `vvp`), version 11 or newer for `-g2012` support

macOS (Homebrew):

```bash
brew install icarus-verilog
```

Ubuntu / Debian:

```bash
sudo apt install iverilog python3
```

Check that both are installed:

```bash
iverilog -V && python3 --version
```

Any SystemVerilog simulator (Vivado xsim, Questa, VCS, Verilator) should also work. Add `rtl/` to the include path so `defines.vh` is found.

## 2. Generate the test vectors

Run the generators from `sim/`, since each script writes its `.hex` file to the current folder and each testbench reads it from there.

```bash
cd sim
```

```bash
python3 ../scripts/fpr_floor_gen_vectors.py
```

To regenerate all of them:

```bash
for s in ../scripts/*_gen_vectors.py; do python3 "$s"; done
```

Each line of a `.hex` file is the input followed by the expected outputs, as 16 hex digits each. The generators use fixed seeds, so the output is reproducible.

## 3. Run a testbench

From `sim/`, compile the testbench with the RTL files it needs, then run it:

```bash
iverilog -g2012 -I ../rtl -o fpr_floor.vvp fpr_floor_tb.sv ../rtl/fpr_floor.sv
```

```bash
vvp -n fpr_floor.vvp
```

A passing run ends with a line like:

```
fpr_floor: checked 210766 vectors, 0 errors -> PASS
```

The first few mismatches, if any, are printed with the input, the result and the expected value.

### Files for each testbench

All RTL files are in `rtl/`.

| Testbench                            | Vector generator                            | RTL files                                                                                   |
|--------------------------------------|---------------------------------------------|---------------------------------------------------------------------------------------------|
| `fpr_add_tb.sv`                      | `fpr_add_gen_vectors.py`                    | `fpr_add.sv fpr_add_norm.sv leading_one_calc.sv`                                            |
| `fpr_mul_tb.sv`                      | `fpr_mul_gen_vectors.py`                    | `fpr_mul_top.sv fpr_mul.sv int64_mul.sv uint64_mul.sv` + multiplier files (*)               |
| `fpr_mul_top_int_tb.sv`              | none (reference in the testbench)           | `fpr_mul_top.sv fpr_mul.sv int64_mul.sv uint64_mul.sv` + (*)                                |
| `mult_check_tb.sv`                   | none (reference in the testbench)           | `karatsuba_mul.sv comba_mul.sv`                                                             |
| `int2fpr_tb.sv`                      | `int2fpr_gen_vectors.py`                    | `int2fpr.sv leading_one_calc.sv`                                                            |
| `fpr_round_tb.sv`                    | `fpr_round_gen_vectors.py`                  | `fpr_round.sv`                                                                              |
| `fpr_floor_tb.sv`                    | `fpr_floor_gen_vectors.py`                  | `fpr_floor.sv`                                                                              |
| `fpr_floor_and_residue_tb.sv`        | `fpr_floor_and_residue_gen_vectors.py`      | `fpr_floor_and_residue.sv leading_one_calc.sv`                                              |
| `fpr_floor_int_fpr_and_residue_tb.sv`| `fpr_floor_int_fpr_and_residue_gen_vectors.py` | `fpr_floor_int_fpr_and_residue.sv fpr_floor_and_residue.sv leading_one_calc.sv`          |
| `fpr_ceil_tb.sv`                     | `fpr_ceil_gen_vectors.py`                   | `fpr_ceil.sv`                                                                               |
| `fpr_ceil_and_residue_tb.sv`         | `fpr_ceil_and_residue_gen_vectors.py`       | `fpr_ceil_and_residue.sv leading_one_calc.sv`                                               |
| `fpr_ceil_int_fpr_and_residue_tb.sv` | `fpr_ceil_int_fpr_and_residue_gen_vectors.py` | `fpr_ceil_int_fpr_and_residue.sv fpr_ceil_and_residue.sv leading_one_calc.sv`             |
| `fpr_trunc_tb.sv`                    | `fpr_trunc_gen_vectors.py`                  | `fpr_trunc.sv`                                                                              |
| `fpr_to_int_tb.sv`                   | `fpr_to_int_gen_vectors.py`                 | `fpr_to_int.sv leading_one_calc.sv`                                                         |
| `fpr_top_tb.sv`                      | `fpr_top_gen_vectors.py` (imports the fma, to_int and div generators) | `fpr_top.sv fpr_add.sv fpr_add_norm.sv fpr_mul.sv fpr_fma.sv fpr_to_int.sv int2fpr.sv int64_mul.sv uint64_mul.sv fpr_div.sv fpr_sqrt.sv fpr_div_sqrt.sv leading_one_calc.sv` + (*) |
| `fpr_fma_tb.sv`                      | `fpr_fma_gen_vectors.py`                    | `fpr_fma_top.sv fpr_fma.sv leading_one_calc.sv` + (*)                                       |
| `fpr_mac_tb.sv`                      | `fpr_mac_gen_vectors.py` (imports `fpr_fma_gen_vectors.py`) | `fpr_mac.sv fpr_fma.sv leading_one_calc.sv` + (*)                           |
| `fpr_butterfly_tb.sv`                | `fpr_butterfly_gen_vectors.py` (imports `fpr_fma_gen_vectors.py`) | `fpr_butterfly.sv fpr_fma.sv fpr_mul.sv fpr_add.sv fpr_add_norm.sv leading_one_calc.sv` + (*) |
| `fpr_div_tb.sv` (`INV` = 0)          | `fpr_div_gen_vectors.py`                    | `fpr_div.sv fpr_inv.sv`                                                                     |
| `fpr_div_tb.sv` (`INV` = 1)          | `fpr_inv_gen_vectors.py`                    | `fpr_div.sv fpr_inv.sv`                                                                     |
| `fpr_sqrt_tb.sv`                     | `fpr_sqrt_gen_vectors.py`                   | `fpr_sqrt.sv`                                                                               |
| `fpr_div_sqrt_tb.sv`                 | reuses the div, inv and sqrt vector files   | `fpr_div_sqrt.sv`                                                                           |
| `leading_one_calc_check_tb.sv`       | none (checks itself)                        | `leading_one_calc.sv`                                                                       |

(*) Multiplier files: `uint_mul_core.sv karatsuba_mul.sv comba_mul.sv`. Add `-DKARATSUBA_MUL` or `-DCOMBA_MUL` to the `iverilog` command to test with that multiplier instead of the default `a * b` (see [Choosing the multiplier](#choosing-the-multiplier)).

For example, the ceil with INT64, FP64 and residue outputs:

```bash
python3 ../scripts/fpr_ceil_int_fpr_and_residue_gen_vectors.py
```

```bash
iverilog -g2012 -I ../rtl -o fpr_ceil_int_fpr_and_residue.vvp fpr_ceil_int_fpr_and_residue_tb.sv ../rtl/fpr_ceil_int_fpr_and_residue.sv ../rtl/fpr_ceil_and_residue.sv ../rtl/leading_one_calc.sv
```

```bash
vvp -n fpr_ceil_int_fpr_and_residue.vvp
```

### Testbenches with parameters

Some testbenches take parameters that match the module parameters (see [Module parameters](#module-parameters)). Set them with `-P <tb>.<NAME>=<value>`:

| Testbench       | Parameters (default first)                                     |
|-----------------|----------------------------------------------------------------|
| `fpr_mul_tb.sv` | `STANDALONE` = 0 (through `fpr_mul_top`) or 1 (`fpr_mul` with `INTERNAL_MULT = 1`, only `fpr_mul.sv` + (*) needed) |
| `fpr_fma_tb.sv` | `FUSED` = 1 or 0, `REG_STAGES` = 1 or 2, `INTERNAL_MULT` = 0 (through `fpr_fma_top`) or 1 |
| `fpr_mac_tb.sv` | `FUSED` = 1 or 0, `REG_STAGES` = 1 or 2, `INTERNAL_MULT` = 0 (testbench supplies the multiplier) or 1 |
| `fpr_butterfly_tb.sv` | `FUSED` = 0 or 1, `REG_STAGES` = 1 or 2 |
| `fpr_div_tb.sv` | `INV` = 0 (`fpr_div`) or 1 (`fpr_inv`), `BITS_PER_CYCLE` = 2 (1..27), `PIPELINED` = 0 or 1 |
| `fpr_sqrt_tb.sv` | `BITS_PER_CYCLE` = 2 (1..27), `PIPELINED` = 0 or 1 |
| `fpr_div_sqrt_tb.sv` | `BITS_PER_CYCLE` = 2 (1..27), `PIPELINED` = 0 or 1 |
| `fpr_top_tb.sv` | the `fpr_top` parameters (see [`fpr_top`](#fpr_top-general-purpose-wrapper)); ops left out must return `out_error` |
| `fpr_to_int_tb.sv` | none. `vvp -n <file>.vvp +VECTORS=<file.hex>` replays another vector file in the same format |

For example, the unfused FMA with 2 register stages and its own multiplier:

```bash
iverilog -g2012 -I ../rtl -P fpr_fma_tb.FUSED=0 -P fpr_fma_tb.REG_STAGES=2 -P fpr_fma_tb.INTERNAL_MULT=1 -o fpr_fma.vvp fpr_fma_tb.sv ../rtl/fpr_fma.sv ../rtl/leading_one_calc.sv ../rtl/uint_mul_core.sv ../rtl/karatsuba_mul.sv ../rtl/comba_mul.sv
```

```bash
vvp -n fpr_fma.vvp
```

The same with the Karatsuba multiplier inside:

```bash
iverilog -g2012 -I ../rtl -DKARATSUBA_MUL -P fpr_fma_tb.FUSED=0 -P fpr_fma_tb.REG_STAGES=2 -P fpr_fma_tb.INTERNAL_MULT=1 -o fpr_fma.vvp fpr_fma_tb.sv ../rtl/fpr_fma.sv ../rtl/leading_one_calc.sv ../rtl/uint_mul_core.sv ../rtl/karatsuba_mul.sv ../rtl/comba_mul.sv
```

The FMA and MAC vector files hold the expected result for both `FUSED = 1` and `FUSED = 0`, and the testbench picks the one that matches. An expected value of `ffffffffffffffff` marks a case that is out of scope for that mode (for example, with `FUSED = 0` the rounded a*b would be subnormal), and the testbench skips it. Both testbenches stream inputs with random idle cycles and check the outputs in order, so they also check the pipelining and, for the MAC, the `in_tready` handshake.

## 4. Run everything

From `sim/`, this generates all the vectors and runs every testbench, printing one result line each:

```bash
R=../rtl
for s in ../scripts/*_gen_vectors.py; do python3 "$s"; done
run() { iverilog -g2012 -I $R -o "$1.vvp" "$1_tb.sv" "${@:2}" && vvp -n "$1.vvp" | grep "vectors"; }
run fpr_add                       $R/fpr_add.sv $R/fpr_add_norm.sv $R/leading_one_calc.sv
run int2fpr                       $R/int2fpr.sv $R/leading_one_calc.sv
run fpr_round                     $R/fpr_round.sv
run fpr_floor                     $R/fpr_floor.sv
run fpr_floor_and_residue         $R/fpr_floor_and_residue.sv $R/leading_one_calc.sv
run fpr_floor_int_fpr_and_residue $R/fpr_floor_int_fpr_and_residue.sv $R/fpr_floor_and_residue.sv $R/leading_one_calc.sv
run fpr_ceil                      $R/fpr_ceil.sv
run fpr_ceil_and_residue          $R/fpr_ceil_and_residue.sv $R/leading_one_calc.sv
run fpr_ceil_int_fpr_and_residue  $R/fpr_ceil_int_fpr_and_residue.sv $R/fpr_ceil_and_residue.sv $R/leading_one_calc.sv
run fpr_trunc                     $R/fpr_trunc.sv
run fpr_to_int                    $R/fpr_to_int.sv $R/leading_one_calc.sv
run leading_one_calc_check        $R/leading_one_calc.sv
run mult_check                    $R/karatsuba_mul.sv $R/comba_mul.sv
for I in 0 1; do for P in 0 1; do for K in 1 2 4 27; do
  iverilog -g2012 -I $R -P fpr_div_tb.INV=$I -P fpr_div_tb.PIPELINED=$P -P fpr_div_tb.BITS_PER_CYCLE=$K -o fpr_div.vvp fpr_div_tb.sv $R/fpr_div.sv $R/fpr_inv.sv && vvp -n fpr_div.vvp | grep "vectors"
done; done; done
for P in 0 1; do for K in 1 2 4 27; do
  iverilog -g2012 -I $R -P fpr_sqrt_tb.PIPELINED=$P -P fpr_sqrt_tb.BITS_PER_CYCLE=$K -o fpr_sqrt.vvp fpr_sqrt_tb.sv $R/fpr_sqrt.sv && vvp -n fpr_sqrt.vvp | grep "vectors"
done; done
for P in 0 1; do for K in 2 27; do
  iverilog -g2012 -I $R -P fpr_div_sqrt_tb.PIPELINED=$P -P fpr_div_sqrt_tb.BITS_PER_CYCLE=$K -o fpr_div_sqrt.vvp fpr_div_sqrt_tb.sv $R/fpr_div_sqrt.sv && vvp -n fpr_div_sqrt.vvp | grep "vectors"
done; done
for D in DEFAULT_MUL KARATSUBA_MUL COMBA_MUL; do
  echo "== multiplier: $D"
  for P in 0 1; do
    iverilog -g2012 -I $R -D$D -P fpr_mul_tb.STANDALONE=$P -o fpr_mul.vvp fpr_mul_tb.sv $R/fpr_mul_top.sv $R/fpr_mul.sv $R/int64_mul.sv $R/uint64_mul.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_mul.vvp | grep "vectors"
  done
  iverilog -g2012 -I $R -D$D -o fpr_mul_top_int.vvp fpr_mul_top_int_tb.sv $R/fpr_mul_top.sv $R/fpr_mul.sv $R/int64_mul.sv $R/uint64_mul.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_mul_top_int.vvp | grep "vectors"
  for F in 1 0; do for S in 1 2; do for I in 0 1; do
    iverilog -g2012 -I $R -D$D -P fpr_fma_tb.FUSED=$F -P fpr_fma_tb.REG_STAGES=$S -P fpr_fma_tb.INTERNAL_MULT=$I -o fpr_fma.vvp fpr_fma_tb.sv $R/fpr_fma_top.sv $R/fpr_fma.sv $R/leading_one_calc.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_fma.vvp | grep "vectors"
    iverilog -g2012 -I $R -D$D -P fpr_mac_tb.FUSED=$F -P fpr_mac_tb.REG_STAGES=$S -P fpr_mac_tb.INTERNAL_MULT=$I -o fpr_mac.vvp fpr_mac_tb.sv $R/fpr_mac.sv $R/fpr_fma.sv $R/leading_one_calc.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_mac.vvp | grep "steps"
  done; done; done
  iverilog -g2012 -I $R -D$D -o fpr_top.vvp fpr_top_tb.sv $R/fpr_top.sv $R/fpr_add.sv $R/fpr_add_norm.sv $R/fpr_mul.sv $R/fpr_fma.sv $R/fpr_to_int.sv $R/int2fpr.sv $R/int64_mul.sv $R/uint64_mul.sv $R/fpr_div.sv $R/fpr_sqrt.sv $R/fpr_div_sqrt.sv $R/leading_one_calc.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_top.vvp | grep "results"
  iverilog -g2012 -I $R -D$D -Pfpr_top_tb.FMA_ONLY_CORE=1 -Pfpr_top_tb.FUSED=0 -Pfpr_top_tb.FMA_REG_STAGES=2 -Pfpr_top_tb.DIVSQRT=1 -Pfpr_top_tb.DIVSQRT_PIPELINED=1 -o fpr_top.vvp fpr_top_tb.sv $R/fpr_top.sv $R/fpr_add.sv $R/fpr_add_norm.sv $R/fpr_mul.sv $R/fpr_fma.sv $R/fpr_to_int.sv $R/int2fpr.sv $R/int64_mul.sv $R/uint64_mul.sv $R/fpr_div.sv $R/fpr_sqrt.sv $R/fpr_div_sqrt.sv $R/leading_one_calc.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_top.vvp | grep "results"
  for F in 0 1; do for S in 1 2; do
    iverilog -g2012 -I $R -D$D -P fpr_butterfly_tb.FUSED=$F -P fpr_butterfly_tb.REG_STAGES=$S -o fpr_butterfly.vvp fpr_butterfly_tb.sv $R/fpr_butterfly.sv $R/fpr_fma.sv $R/fpr_mul.sv $R/fpr_add.sv $R/fpr_add_norm.sv $R/leading_one_calc.sv $R/uint_mul_core.sv $R/karatsuba_mul.sv $R/comba_mul.sv && vvp -n fpr_butterfly.vvp | grep "vectors"
  done; done
done
```

The full run takes about 40 minutes, most of it in the FMA, MAC and butterfly runs, which are repeated for each of the three multipliers. To check only one multiplier, change the `for D in ...` list. The `.vvp` files are build outputs and can be deleted afterwards.

## `fpr_top`: general-purpose wrapper

> **Note:** `fpr_top` is a convenience wrapper for trying the units together. It is **not** tuned for any particular FALCON implementation: it accepts one op per cycle, shares a single multiplier, and uses a generic output path. For a real design, pick the individual modules you need (each one is documented below and has its own testbench) and connect them for your own schedule.

`fpr_top` replaces the old `fpr_top_full` and `fpr_top_partial`. Compared with them:

- the output is chosen by the unit that produced the result, not by the op currently on the input (before, issuing a different op on the next cycle routed the previous result to the wrong place);
- results from units with different latencies cannot collide (see below);
- the floor, ceil, trunc and round modes share one `fpr_to_int` unit;
- parameters decide which units are built.

**Ports:** `in_tvalid` / `in_tready`, `in_op` (5 bits), `in_tuser` (`TUSER_W` bits, passed through), operands `in1_tdata` (a), `in2_tdata` (b), `in3_tdata` (c), and on the output `out_tvalid`, `out_op`, `out_tuser`, `out_error`, `out_tdata`, `out_tdata2`, `out_tdata3`.

**Ops** (`rtl/fpr_top_ops.vh`, include it to use the names):

| `in_op` | Name | Result |
|---------|------|--------|
| `0x00` / `0x01` | `FPR_OP_ADD` / `FPR_OP_SUB` | `a + b` / `a - b` |
| `0x02` | `FPR_OP_MUL` | `a * b` |
| `0x03`..`0x06` | `FPR_OP_FMA`, `FMS`, `FNMA`, `FNMS` | `a*b + c`, `a*b - c`, `-a*b + c`, `-a*b - c` |
| `0x08`..`0x0B` | `FPR_OP_FLOOR`, `CEIL`, `TRUNC`, `ROUND` | `out_tdata` = int64, `out_tdata2` = the same value as a double, `out_tdata3` = residue `a - value` |
| `0x0C` | `FPR_OP_INT2FPR` | `a` (signed int64) as a double |
| `0x10` / `0x11` / `0x12` | `FPR_OP_DIV` / `INV` / `SQRT` | `a / b` / `1 / a` / `sqrt(a)` |
| `0x14` | `FPR_OP_INT64_MUL` | `int64_mul` result: `out_tdata` = low 64 bits, `out_tdata2` = high 64 bits |
| `0x15` | `FPR_OP_UINT64_MUL` | full unsigned 128-bit `a * b`, split the same way |

**Parameters** (default first):

| Parameter | Values | Meaning |
|-----------|--------|---------|
| `INCLUDE_ADD`, `INCLUDE_MUL`, `INCLUDE_FMA` | 1 / 0 | `fpr_add`, `fpr_mul`, `fpr_fma` |
| `FMA_ONLY_CORE` | 0 / 1 | 1: no `fpr_add` / `fpr_mul`; add, sub and mul run on `fpr_fma` as `a * 1.0 + b` and `a * b + (-0)`. Still bit-exact; smaller but slower |
| `FUSED`, `FMA_REG_STAGES` | 1 / 0, 1 / 2 | passed to `fpr_fma` |
| `INCLUDE_TO_INT` | 1 / 0 | `fpr_to_int` (floor / ceil / trunc / round) |
| `INCLUDE_INT2FPR` | 1 / 0 | `int2fpr` |
| `INCLUDE_INT_MUL` | 1 / 0 | `int64_mul` and `uint64_mul` |
| `DIVSQRT` | 2 / 1 / 0 | `fpr_div_sqrt` / `fpr_div` + `fpr_sqrt` / none |
| `DIVSQRT_BITS_PER_CYCLE`, `DIVSQRT_PIPELINED` | 2, 0 | passed to the div / sqrt units |
| `OPERAND_ISOLATION` | 1 / 0 | hold the inputs of idle units at 0, so they do not switch |
| `TUSER_W` | 8 | width of `in_tuser` / `out_tuser` |

`fpr_mul`, `fpr_fma`, `int64_mul` and `uint64_mul` share one 64x64 `uint_mul_core` (chosen in `defines.vh`). This is safe because only one op is accepted per cycle.

**Handshake and results:**

- An op is accepted when `in_tvalid & in_tready`.
- Every op has a fixed latency: 1 cycle for most ops, `FMA_REG_STAGES` for the FMA ops (and for add/sub/mul when `FMA_ONLY_CORE = 1`), and `ceil(54 / K) + 2` (iterative) or `+ 1` (pipelined) for div / inv / sqrt.
- When an op is accepted it reserves the cycle in which its result will come out. `in_tready` is low if that cycle is already taken, or if the unit is busy (the iterative div / sqrt). So results never collide, but they can come back out of order: use `out_op` and `out_tuser` to match them.
- An op whose unit is not built is accepted and comes back after 1 cycle with `out_error = 1` (it does not stall).

`fpr_top_tb.sv` streams a random mix of all ops with random idle cycles, matches results by `out_tuser`, and checks that ops left out by the parameters return `out_error`.

## Module parameters

### `fpr_to_int`: floor, ceil, trunc and round in one unit

`fpr_to_int_mode` selects the rounding: `2'b00` floor, `2'b01` ceil, `2'b10` trunc, `2'b11` round (nearest, ties to even, = FALCON `fpr_rint`). There are three outputs, with 1-cycle latency:

- `out_int`: the rounded value as a signed int64;
- `out_fpr`: the same value as a double (= `fpr_of(out_int)`);
- `out_residue`: `x - out_fpr` as a double (= `fpr_sub(x, fpr_of(out_int))`).

One split of |x| into integer part I and fraction F serves all four modes. The mode only decides whether the magnitude goes up by one, and then `int = (sign ? ~I : I) + (sign ? ~up : up)` with a single adder. The double value and the residue follow from the same `up`, and the residue is exact except for the `1 - |x|` case, which is rounded as in `fpr_floor_and_residue`.

It gives the same results, bit for bit, as `fpr_floor`, `fpr_ceil`, `fpr_trunc`, `fpr_round` and the `*_and_residue` / `*_int_fpr_and_residue` modules on their own vector files (checked by replaying them with `+VECTORS=`), using one shifter, one incrementer and one residue normalizer. The single-mode modules are kept for designs that need only one mode. `FPR_OUT = 0` and `RESIDUE_OUT = 0` remove the logic for those outputs.

Inputs: any. Inf, NaN and |x| >= 2^63 saturate the int64 by sign (the double output is then x, the residue +0), and subnormals are handled as the tiny values they are.

### Choosing the multiplier

Every multiply goes through `uint_mul_core`, an unsigned N x N -> 2N combinational multiplier (0 latency) that is used in two places:

- the shared 64x64 multiplier in `fpr_mul_top`, `fpr_fma_top` and `fpr_top`;
- the internal 53x53 multiplier of `fpr_mul` / `fpr_fma` / `fpr_mac` with `INTERNAL_MULT = 1`.

The implementation is chosen once, in `rtl/defines.vh` (uncomment one line), or on the tool command line (`-DKARATSUBA_MUL`, `-DCOMBA_MUL`, or `+define+...` for other simulators). If neither is defined, `DEFAULT_MUL` is used.

| Define          | Module          | How it works | Size parameter (on `uint_mul_core`) |
|-----------------|-----------------|--------------|------------------|
| `DEFAULT_MUL`   | none            | `a * b`, left to the synthesis tool | none |
| `KARATSUBA_MUL` | `karatsuba_mul.sv` | Recursive Karatsuba: 3 half-size multiplies per level instead of 4, down to plain multiplies of at most `KARATSUBA_BASE` bits | `KARATSUBA_BASE` = 18 (match the DSP input width) |
| `COMBA_MUL`     | `comba_mul.sv`  | Comba (product scanning): `COMBA_LIMB`-bit limb products summed column by column, with the carry passed to the next column | `COMBA_LIMB` = 16 |

All three are combinational, so the multicycle path constraints in `constraints/timing_constraints.xdc` apply in the same way. `karatsuba_mul` and `comba_mul` can also be used on their own for any width N. `mult_check_tb.sv` checks both against `a * b` at 64x64 and 53x53, for several base and limb sizes.

### Integer multiplies in `fpr_mul_top`

The integer multiplies share the same 64x64 multiplier as the fp multiply:

| `fpr_mul_op` | Operation | Output |
|--------------|-----------|--------|
| `2'b00`      | fp mul    | `fpr_mul_out_*` |
| `2'b01`      | int64 mul, sign-magnitude (`int64_mul`, as used for ApproxExp): `{sign, 1'b0, a[62:0] * b[62:0]}` | `int64_mul_out_*` |
| `2'b10`      | uint64 mul, the full 128-bit unsigned `a * b` (`uint64_mul`) | `uint64_mul_out_*` |

Older designs that drive a 1-bit `fpr_mul_op` (0 / 1) still work as before, since the value is zero-extended. `fpr_mul_top_int_tb.sv` checks both integer paths, switching the op every cycle. `fpr_top` has the same two ops (`FPR_OP_INT64_MUL`, `FPR_OP_UINT64_MUL`).

### Multiplier sharing (`INTERNAL_MULT`)

`fpr_mul`, `fpr_fma` and `fpr_mac` do not have to contain their own 53x53 multiplier. Each one has the same three ports to an outside 64x64 unsigned multiplier, so one multiplier (or the Karatsuba/Comba options in `defines.vh`) can be shared between units:

| Port                         | Direction | Meaning                                    |
|------------------------------|-----------|--------------------------------------------|
| `uint64_mult_in1`            | output    | `{11'b0, 1.mantissa}` of the first operand |
| `uint64_mult_in2`            | output    | `{11'b0, 1.mantissa}` of the second operand |
| `uint64_mult_result [127:0]` | input     | `uint64_mult_in1 * uint64_mult_in2`, same cycle (combinational) |

| `INTERNAL_MULT` | Behavior |
|-----------------|----------|
| 0 (default)     | Shared: the product comes from `uint64_mult_result`. `fpr_mul_top` (with `int64_mul`) and `fpr_fma_top` attach the default multiplier. |
| 1               | Standalone: the product is computed inside the module. `uint64_mult_result` is ignored (tie it to 0), and the `uint64_mult_in*` outputs can be left open. |

The default is 0, so existing designs (for example `fpr_mul_top`) behave the same as before.

### `fpr_fma`: multiply-add

`out = (+/-)(a * b) + (+/-)c`, round to nearest even. Inputs are `in1` = a, `in2` = b, `in3` = c.

| `fpr_fma_op` | Result      |
|--------------|-------------|
| `2'b00`      | `a*b + c`   |
| `2'b01`      | `a*b - c`   |
| `2'b10`      | `-a*b + c`  |
| `2'b11`      | `-a*b - c`  |

| Parameter    | Values | Meaning |
|--------------|--------|---------|
| `FUSED`      | 1 (default) | True fused multiply-add: the exact `a*b + c` is rounded once. |
|              | 0      | `a*b` is rounded to a double first, so the result is bit-exact with `fpr_add(fpr_mul(a, b), c)`, as in FALCON's reference code. |
| `REG_STAGES` | 1 (default) | 1-cycle latency, one input per cycle. |
|              | 2      | 2-cycle latency, one input per cycle. There is an extra register after the multiplier (and the product rounding when `FUSED = 0`). |
| `INTERNAL_MULT` | 0 / 1 | See above. `fpr_fma_top` is `fpr_fma` with the default multiplier attached. |

Scope: inputs are zero or normal, and the result must be zero or normal. With `FUSED = 1`, a*b on its own may be outside the double range, as long as c brings the result back into range. With `FUSED = 0`, the rounded a*b must also be zero or normal (as with `fpr_mul`). The output register only updates on a valid input.

### `fpr_mac`: accumulating multiply-add

`fpr_mac` wraps `fpr_fma` and feeds the result back as c, so the `fpr_fma` output register holds the running sum:

- `acc <= (+/-)(a * b) + (+/-)acc`. `fpr_mac_op[1]` negates a*b and `fpr_mac_op[0]` negates acc, as above.
- `fpr_mac_in_acc_clear = 1` starts a new sum: `acc <= (+/-)(a * b)`. Internally the old acc is replaced with -0, so the first product is passed through exactly, including the sign of a zero.
- `fpr_mac_out_tdata` is the accumulator, updated on each accepted input (`fpr_mac_out_tvalid` pulses).
- An input is accepted when `fpr_mac_in_tvalid & fpr_mac_in_tready`.

| `REG_STAGES` | Throughput | `fpr_mac_in_tready` |
|--------------|------------|---------------------|
| 1            | one accumulate per cycle | always 1 |
| 2            | one accumulate every 2 cycles (the next input needs the previous result) | 0 for the cycle after each accepted input |

`FUSED` and `INTERNAL_MULT` are passed through to `fpr_fma`.

### `fpr_butterfly`: FFT butterfly

One radix-2 butterfly on complex doubles per cycle, as in FALCON's `FFT` / `iFFT` (`fft.c`). The FFT and the iFFT, which also back `poly_split_fft` / `poly_merge_fft`, are layers of these butterflies.

| `fpr_butterfly_in_mode` | Operation |
|-------------------------|-----------|
| 0 (FFT, Cooley-Tukey)   | `t = y * s;  x' = x + t;  y' = x - t` |
| 1 (iFFT, Gentleman-Sande) | `x' = x + y;  y' = (x - y) * s` |

`fpr_butterfly_in_conj_s = 1` uses `conj(s)`, so the iFFT can read the same twiddle table as the FFT (FALCON's iFFT uses the conjugated twiddles).

The complex multiply follows FALCON's `FPC_MUL`: `re = fl(fl(p_re*s_re) - fl(p_im*s_im))` and `im = fl(fl(p_re*s_im) + fl(p_im*s_re))`. Each component is one `fpr_mul` and one `fpr_fma`, and then 4 `fpr_add` units do the additions and subtractions.

| Parameter    | Values | Meaning |
|--------------|--------|---------|
| `FUSED`      | 0 (default) | Bit-exact with FALCON's reference code. |
|              | 1      | Each `fpr_fma` rounds `a*b + c` once, giving one rounding less per component. This is not bit-exact with FALCON. |
| `REG_STAGES` | 1 (default) / 2 | Passed to `fpr_fma`. The latency is `REG_STAGES + 2` cycles in both modes. |

The forward pipeline is MUL -> FMA -> ADD and the inverse is ADD -> MUL -> FMA, so the 4 adders are shared between the two modes instead of being duplicated. As a result, the mode can only change once the pipeline is empty: `fpr_butterfly_in_tready` drops while butterflies of the other mode are still in flight, and an input is accepted when `in_tvalid & in_tready`. In a whole FFT the mode never changes, so a butterfly is accepted every cycle.

The 4 mantissa multipliers are inside the unit (`INTERNAL_MULT = 1` on the `fpr_mul` and `fpr_fma` instances), because all 4 are busy every cycle. They still use `uint_mul_core`, so `defines.vh` picks the default, Karatsuba or Comba multiplier.

Scope: as for the other units, inputs, intermediate products and sums, and outputs are zero or normal doubles. This is always true for FFT data in FALCON.

### `fpr_div` and `fpr_inv`: division and reciprocal

`fpr_div` computes `a / b` and `fpr_inv` computes `1 / x`, both rounded to nearest even. Division is correctly rounded, so both are bit-exact with FALCON's `fpr_div` and `fpr_inv` (`fpr_inv(x) = fpr_div(1.0, x)`). `fpr_inv` is `fpr_div` with the dividend tied to 1.0, and has the same parameters and handshake.

The quotient comes from a radix-2 restoring digit recurrence on the significands, with no multipliers. The dividend is pre-shifted so the quotient is in [1, 2), each step produces one quotient bit with a compare and subtract, 54 bits (53 + guard) are computed, and a non-zero remainder sets the sticky bit.

| Parameter        | Values | Meaning |
|------------------|--------|---------|
| `BITS_PER_CYCLE` | 1..27 (default 2) | Quotient bits per step (K chained compare/subtract stages). The divide takes `ITER = ceil(54 / K)` steps. |
| `PIPELINED`      | 0 (default) | Iterative: one recurrence unit. Latency `ITER + 2` cycles, one new input every `ITER + 1` cycles, and `in_tready` stays low while busy. |
|                  | 1      | Fully pipelined: one register stage per step. Latency `ITER + 1` cycles, one input per cycle, `in_tready` always 1. About `ITER` times the area of the iterative version. |

For example, `BITS_PER_CYCLE = 2` gives 27 steps (28 cycles per divide when iterative), and `BITS_PER_CYCLE = 4` gives 14 steps with a longer critical path per step.

An input is accepted when `in_tvalid & in_tready`, and the output data only updates when `out_tvalid` is set.

Scope: a is zero or normal, b is normal, and the result is zero or normal. Division by zero is not handled (FALCON never divides by zero).

### `fpr_sqrt`: square root

`fpr_sqrt` computes `sqrt(x)`, rounded to nearest even. Square root is correctly rounded, so it is bit-exact with FALCON's `fpr_sqrt`. It has the same parameters (`BITS_PER_CYCLE` 1..27, `PIPELINED` 0 or 1), latency, throughput and `in_tready` handshake as `fpr_div` (see the table above), so the two can be swapped in a schedule.

The root comes from a restoring digit-by-digit square root on the significand, with no multipliers. For an odd unbiased exponent the significand is doubled, so the root is in [1, 2) and the result exponent is just halved. Each step brings down 2 bits of the significand and produces 1 root bit. 54 bits (53 + guard) are computed, and a non-zero remainder sets the sticky bit.

Scope: x is +/-0 or a positive normal number, and the result is then always normal. `sqrt(-0) = -0`. Negative inputs are not handled (FALCON only takes square roots of non-negative values).

### `fpr_div_sqrt`: shared division / square root unit

`fpr_div_sqrt` does both operations in one recurrence, chosen per input by `fpr_div_sqrt_op`:

| `fpr_div_sqrt_op` | Result | Inputs used |
|-------------------|--------|-------------|
| 0 | `a / b` (for `1 / x`, set a = 1.0) | `in1` = a, `in2` = b |
| 1 | `sqrt(a)` | `in1` = a (`in2` is ignored) |

It uses the same algorithms, parameters (`BITS_PER_CYCLE`, `PIPELINED`), latency, throughput and `in_tready` handshake as `fpr_div` and `fpr_sqrt`, and its results are bit-exact with them. With `PIPELINED = 1` the op travels with each input, so divides and square roots can be mixed in back-to-back cycles.

Both options are kept so that designers can choose:

| | `fpr_div` + `fpr_sqrt` (+ `fpr_inv`) | `fpr_div_sqrt` |
|---|---|---|
| Area | Two recurrences, two sets of registers and rounding logic | One of each, plus muxes, so smaller |
| Concurrency | A divide and a square root can run at the same time | One at a time (iterative), or interleaved but sharing the stages (pipelined) |
| Critical path | Each recurrence has its own width (the divide remainder is a few bits narrower) | Slightly longer: muxes in every chained step, and every step uses the wider square-root remainder |
| `fpr_inv` | The dividend is a constant 1.0, so synthesis can trim a little | Pass a = 1.0 |

In FALCON the divides and reciprocals happen while the LDL tree is built, and the square roots when the tree leaves are normalized afterwards. So the two rarely compete for the unit, and the shared version usually loses no throughput.

## Notes

- `rtl/defines.vh` defines `FPGA_DESIGN`, which gives the output registers initial values. It also selects the multiplier (see [Choosing the multiplier](#choosing-the-multiplier)).
- The units target FALCON and do not support NaN, infinity, overflow/underflow or subnormals. Each generator's reference model follows the scope stated in the header comment of its RTL file and script. For example, `fpr_floor` and `fpr_ceil` saturate NaN and infinity by sign, while the residue units are only tested on zero and normal inputs.
