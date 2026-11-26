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
| `fpr_mul_tb.sv`                      | `fpr_mul_gen_vectors.py`                    | `fpr_mul_top.sv fpr_mul.sv int64_mul.sv`                                                    |
| `int2fpr_tb.sv`                      | `int2fpr_gen_vectors.py`                    | `int2fpr.sv leading_one_calc.sv`                                                            |
| `fpr_round_tb.sv`                    | `fpr_round_gen_vectors.py`                  | `fpr_round.sv`                                                                              |
| `fpr_floor_tb.sv`                    | `fpr_floor_gen_vectors.py`                  | `fpr_floor.sv`                                                                              |
| `fpr_floor_and_residue_tb.sv`        | `fpr_floor_and_residue_gen_vectors.py`      | `fpr_floor_and_residue.sv leading_one_calc.sv`                                              |
| `fpr_floor_int_fpr_and_residue_tb.sv`| `fpr_floor_int_fpr_and_residue_gen_vectors.py` | `fpr_floor_int_fpr_and_residue.sv fpr_floor_and_residue.sv leading_one_calc.sv`          |
| `fpr_ceil_tb.sv`                     | `fpr_ceil_gen_vectors.py`                   | `fpr_ceil.sv`                                                                               |
| `fpr_ceil_and_residue_tb.sv`         | `fpr_ceil_and_residue_gen_vectors.py`       | `fpr_ceil_and_residue.sv leading_one_calc.sv`                                               |
| `fpr_ceil_int_fpr_and_residue_tb.sv` | `fpr_ceil_int_fpr_and_residue_gen_vectors.py` | `fpr_ceil_int_fpr_and_residue.sv fpr_ceil_and_residue.sv leading_one_calc.sv`             |
| `leading_one_calc_check_tb.sv`       | none (checks itself)                        | `leading_one_calc.sv`                                                                       |

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

## 4. Run everything

From `sim/`, this generates all the vectors and runs every testbench, printing one result line each:

```bash
R=../rtl
for s in ../scripts/*_gen_vectors.py; do python3 "$s"; done
run() { iverilog -g2012 -I $R -o "$1.vvp" "$1_tb.sv" "${@:2}" && vvp -n "$1.vvp" | grep "vectors"; }
run fpr_add                       $R/fpr_add.sv $R/fpr_add_norm.sv $R/leading_one_calc.sv
run fpr_mul                       $R/fpr_mul_top.sv $R/fpr_mul.sv $R/int64_mul.sv
run int2fpr                       $R/int2fpr.sv $R/leading_one_calc.sv
run fpr_round                     $R/fpr_round.sv
run fpr_floor                     $R/fpr_floor.sv
run fpr_floor_and_residue         $R/fpr_floor_and_residue.sv $R/leading_one_calc.sv
run fpr_floor_int_fpr_and_residue $R/fpr_floor_int_fpr_and_residue.sv $R/fpr_floor_and_residue.sv $R/leading_one_calc.sv
run fpr_ceil                      $R/fpr_ceil.sv
run fpr_ceil_and_residue          $R/fpr_ceil_and_residue.sv $R/leading_one_calc.sv
run fpr_ceil_int_fpr_and_residue  $R/fpr_ceil_int_fpr_and_residue.sv $R/fpr_ceil_and_residue.sv $R/leading_one_calc.sv
run leading_one_calc_check        $R/leading_one_calc.sv
```

The whole run takes about a minute. The `.vvp` files are build outputs and can be deleted afterwards.

## Notes

- `rtl/defines.vh` defines `FPGA_DESIGN`, which gives the output registers initial values. It also selects the multiplier used by `int64_mul.sv`.
- The units target FALCON and do not support NaN, infinity, overflow/underflow or subnormals. Each generator's reference model follows the scope stated in the header comment of its RTL file and script. For example, `fpr_floor` and `fpr_ceil` saturate NaN and infinity by sign, while the residue units are only tested on zero and normal inputs.
