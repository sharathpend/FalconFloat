
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_inv_vectors.hex for fpr_div_tb.sv (INV = 1).
# Each line: <1.0 hex><x hex><expected 1 / x hex>  (same format as fpr_div_vectors.hex)
# Reference: IEEE double 1.0 / x, round to nearest even (= FALCON's fpr_inv).
# Only in-scope cases are written: x is normal and 1 / x is normal.
import random
from fpr_fma_gen_vectors import d2b, mkd, rnd
from fpr_div_gen_vectors import ref, M52

ONE = d2b(1.0)

def main():
    random.seed(51)
    v = []
    def add(x):
        q = ref(ONE, x)
        if q is not None: v.append((ONE, x, q))
    for e in range(1, 2047):                             # every exponent
        for m in (0, 1, M52, 1 << 51, random.getrandbits(52)):
            add(mkd(random.getrandbits(1), e, m))
    for _ in range(80000):
        add(rnd(900, 1150))
    for _ in range(20000):                               # mantissas near 1 and near 2
        add(mkd(random.getrandbits(1), random.randint(1000, 1046), random.getrandbits(random.randint(0, 20))))
        add(mkd(random.getrandbits(1), random.randint(1000, 1046), M52 - random.getrandbits(random.randint(0, 20))))
    with open('fpr_inv_vectors.hex', 'w') as f:
        for a, x, q in v: f.write(f"{a:016x}{x:016x}{q:016x}\n")
    print(f"Wrote {len(v)} vectors to fpr_inv_vectors.hex")

if __name__ == '__main__':
    main()
