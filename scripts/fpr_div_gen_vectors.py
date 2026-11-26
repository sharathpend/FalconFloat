
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_div_vectors.hex for fpr_div_tb.sv (INV = 0).
# Each line: <a hex><b hex><expected a / b hex>
# Reference: IEEE double division, round to nearest even (= FALCON's fpr_div).
# Only in-scope cases are written: a is zero or normal, b is normal, a / b is zero or normal.
import random
from fpr_fma_gen_vectors import d2b, b2d, mkd, ok, rnd

M52 = (1 << 52) - 1

def ref(a, b):
    r = b2d(a) / b2d(b)
    if not ok(r) or (r == 0 and b2d(a) != 0): return None
    return d2b(r)

def main():
    random.seed(50)
    v = []
    def add(a, b):
        q = ref(a, b)
        if q is not None: v.append((a, b, q))
    special = [0, 1, 2, M52, M52 - 1, 1 << 51, (1 << 51) - 1, (1 << 51) + 1, 0x5555555555555, 0xAAAAAAAAAAAAA]
    for ma in special:                                   # mantissa corner pairs, every sign
        for mb in special:
            for s in range(4):
                add(mkd(s >> 1, 1023, ma), mkd(s & 1, 1023, mb))
                add(mkd(s >> 1, 1100, ma), mkd(s & 1, 990, mb))
    for s in range(4):
        add(mkd(s >> 1, 0, 0), mkd(s & 1, 1023, 12345)) # +/-0 / b
    for _ in range(60000):                               # random, results well in range
        add(rnd(900, 1150), rnd(900, 1150))
    for _ in range(30000):                               # 1.a close to 1.b (q near 1, a_lt_b boundary)
        mb = random.getrandbits(52)
        ma = (mb + random.randint(-3, 3)) & M52
        add(mkd(random.getrandbits(1), random.randint(1000, 1046), ma), mkd(random.getrandbits(1), random.randint(1000, 1046), mb))
    for _ in range(30000):                               # a = b * q rounded, then nudged by up to 2 ulps
        b = rnd(1000, 1046)
        q = b2d(rnd(1015, 1031))
        a = d2b(b2d(b) * q) + random.randint(-2, 2)
        add(a, b)
    for _ in range(20000):                               # exact quotients: small integers
        q, b = random.randint(1, 1 << 20), random.randint(1, 1 << 30)
        add(d2b(float(q * b) * random.choice([-1, 1])), d2b(float(b)))
    for _ in range(20000):                               # results near the ends of the exponent range
        add(rnd(1, 2046), rnd(1, 2046))
        add(mkd(random.getrandbits(1), random.randint(1, 30), random.getrandbits(52)), rnd(1000, 1060))
        add(mkd(random.getrandbits(1), random.randint(2016, 2046), random.getrandbits(52)), rnd(990, 1050))
    with open('fpr_div_vectors.hex', 'w') as f:
        for a, b, q in v: f.write(f"{a:016x}{b:016x}{q:016x}\n")
    print(f"Wrote {len(v)} vectors to fpr_div_vectors.hex")

if __name__ == '__main__':
    main()
