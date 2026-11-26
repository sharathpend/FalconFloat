
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_sqrt_vectors.hex for fpr_sqrt_tb.sv.
# Each line: <x hex><expected sqrt(x) hex>
# Reference: IEEE double square root, round to nearest even (= FALCON's fpr_sqrt).
# Inputs are +/-0 or positive normal numbers (sqrt(-0) = -0).
import math, random
from fpr_fma_gen_vectors import d2b, b2d, mkd

M52 = (1 << 52) - 1

def ref(x): return d2b(math.sqrt(b2d(x)))

def main():
    random.seed(60)
    v = [0, 1 << 63]
    for e in range(1, 2047):                             # every exponent (odd and even)
        for m in (0, 1, 2, M52, M52 - 1, 1 << 51, (1 << 51) - 1, random.getrandbits(52)):
            v.append(mkd(0, e, m))
    for _ in range(80000):                               # random
        v.append(mkd(0, random.randint(1, 2046), random.getrandbits(52)))
    for _ in range(40000):                               # perfect squares (zero remainder) and +/- 1..2 ulp
        r = d2b(random.uniform(1.0, 2.0) * 2.0 ** random.randint(-500, 500))
        r &= ~((1 << random.randint(26, 52)) - 1)        # short root, so r * r is exact
        sq = d2b(b2d(r) * b2d(r))
        for d in (0, 0, -2, -1, 1, 2):
            v.append(sq + d)
    for _ in range(20000):                               # mantissas near 1 and near 2, both exponent parities
        e = random.randint(1000, 1046)
        v.append(mkd(0, e, random.getrandbits(random.randint(0, 24))))
        v.append(mkd(0, e, M52 - random.getrandbits(random.randint(0, 24))))
    with open('fpr_sqrt_vectors.hex', 'w') as f:
        for x in v: f.write(f"{x:016x}{ref(x):016x}\n")
    print(f"Wrote {len(v)} vectors to fpr_sqrt_vectors.hex")

if __name__ == '__main__':
    main()
