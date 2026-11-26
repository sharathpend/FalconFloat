
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_mac_vectors.hex for fpr_mac_tb.sv.
# Each line: <a hex><b hex><op 1 hex digit><acc_clear 1 hex digit><expected acc FUSED=1 hex><expected acc FUSED=0 hex>
#   acc <= (+/-)(a * b) + (+/-)acc, op[1] negates a * b, op[0] negates acc.
#   acc_clear = 1: acc <= (+/-)(a * b).
# Lines are applied in order. Chains of 1..32 steps start with a clear.
# The references are the ones in fpr_fma_gen_vectors.py, applied step by step.
import random
from fpr_fma_gen_vectors import ref_fused, ref_unfused, rnd, INVALID

random.seed(31)

lines = []
acc_f = acc_u = 0
while len(lines) < 60000:
    chain = random.randint(1, 32)
    lo, hi = random.choice([(1015, 1031), (1020, 1026), (900, 1150)])
    for i in range(chain):
        clear = 1 if i == 0 else int(random.random() < 0.02)
        a = 0 if random.random() < 0.02 else rnd(lo, hi)
        b = rnd(lo, hi)
        op = random.getrandbits(2)
        cf = ((~op & 1) << 63) if clear else acc_f   # cleared acc = -0 after op[0]
        cu = ((~op & 1) << 63) if clear else acc_u
        acc_f, acc_u = ref_fused(a, b, cf, op), ref_unfused(a, b, cu, op)
        lines.append(f"{a:016x}{b:016x}{op:01x}{clear:01x}{acc_f:016x}{acc_u:016x}\n")
        if acc_f == INVALID or acc_u == INVALID: break

with open('fpr_mac_vectors.hex', 'w') as f: f.writelines(lines)
print(f"Wrote {len(lines)} vectors to fpr_mac_vectors.hex")
