
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_fma_vectors.hex for fpr_fma_tb.sv.
# Each line: <a hex><b hex><c hex><op 1 hex digit><expected FUSED=1 hex><expected FUSED=0 hex>
#   op[1] negates a * b, op[0] negates c.
# FUSED=1: exact (+/-)a*b + (+/-)c rounded once to nearest even (computed with Fraction).
# FUSED=0: fl(fl(a*b) + c), bit-exact with fpr_add(fpr_mul(a, b), c).
# An expected value of ffffffffffffffff means out of scope for that mode (the result,
# or for FUSED=0 the rounded product, is not zero or normal); the testbench skips it.
import struct, math, random
from fractions import Fraction

INVALID = 0xFFFFFFFFFFFFFFFF
M52 = (1 << 52) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m

def ok(x): return x == 0 or (not math.isinf(x) and abs(x) >= 2.0**-1022)

def ref_fused(a, b, c, op):
    A, B, C = b2d(a), b2d(b), b2d(c)
    sp = (a >> 63) ^ (b >> 63) ^ (op >> 1)
    sc = (c >> 63) ^ (op & 1)
    exact = Fraction(A) * Fraction(B) * (-1 if op >> 1 else 1) + Fraction(C) * (-1 if op & 1 else 1)
    if exact == 0:
        return (sp & sc) << 63 if (A == 0 or B == 0) and C == 0 else 0
    try: r = float(exact)                # int / int: correctly rounded
    except OverflowError: return INVALID
    return d2b(r) if ok(r) else INVALID

def ref_unfused(a, b, c, op):
    A, B, C = b2d(a), b2d(b), b2d(c)
    p = A * B
    if not ok(p) or (p == 0 and A != 0 and B != 0): return INVALID
    if op >> 1: p = -p
    if op & 1: C = -C
    r = p + C
    return d2b(r) if ok(r) else INVALID

def rnd(elo, ehi): return mkd(random.getrandbits(1), random.randint(elo, ehi), random.getrandbits(52))

def main():
    random.seed(30)
    v = []
    def add(a, b, c, op=None):
        v.append((a, b, c, random.getrandbits(2) if op is None else op))

    z = [0, 1 << 63]
    one = d2b(1.0)
    for a in z + [one]:                                  # zeros with every sign and op
        for b in z + [d2b(-3.0)]:
            for c in z + [d2b(5.0), d2b(-5.0)]:
                for op in range(4): add(a, b, c, op)
    for op in range(4):
        add(mkd(0, 1023, M52), mkd(0, 1023, M52), 0, op)  # product rounds up into the exponent
        add(mkd(0, 1023, M52), mkd(0, 1023, M52), mkd(1, 1024, 0), op)
    for _ in range(40000):                               # general, results well in range
        add(rnd(1000, 1046), rnd(1000, 1046), rnd(990, 1056))
    for d in range(-140, 141):                           # every alignment distance between a*b and c
        for _ in range(150):
            a, b = rnd(1020, 1026), rnd(1020, 1026)
            ep = ((a >> 52) & 0x7FF) + ((b >> 52) & 0x7FF) - 1023
            add(a, b, rnd(ep + d, ep + d))
    for _ in range(30000):                               # cancellation: c close to -a*b
        a, b, op = rnd(1000, 1046), rnd(1000, 1046), random.getrandbits(2)
        p = b2d(a) * b2d(b) * (-1 if op >> 1 else 1)
        cb = d2b(-p) ^ random.choice([0, 0, 1, 2, 3, random.getrandbits(8), random.getrandbits(30)])
        add(a, b, cb ^ ((op & 1) << 63), op)
    for _ in range(20000):                               # integers: exact halfway cases for rounding
        a = d2b(float(random.randint(1 << 26, 1 << 27)) * random.choice([-1, 1]))
        b = d2b(float(random.randint(1 << 26, 1 << 27)))
        add(a, b, d2b(float(random.getrandbits(54)) * random.choice([-1, 1])))
    sparse = lambda: random.choice([0, 1, 2, 3, M52, M52 - 1, 1 << 51, random.getrandbits(4), random.getrandbits(4) << 48,
                                    (1 << random.randint(0, 51)) | 1])
    for _ in range(40000):                               # a*b near half an ulp of c: sticky, ties and rounding carry
        a, b = mkd(random.getrandbits(1), random.randint(1015, 1031), sparse()), mkd(random.getrandbits(1), 1023, sparse())
        ep = ((a >> 52) & 0x7FF) + ((b >> 52) & 0x7FF) - 1023
        add(a, b, mkd(random.getrandbits(1), ep + random.randint(50, 60), random.choice([0, M52, sparse(), random.getrandbits(52)])))
        add(a, b, rnd(ep - 200, ep - 54))                # c only reaches the sticky bit (breaks exact product ties)
    for _ in range(5000):                                # product outside the double range, c brings it back
        add(rnd(1, 300), rnd(1, 300), rnd(900, 1100))
        add(rnd(1700, 2046), rnd(1, 400), rnd(1400, 1500))
    for _ in range(20000):                               # any normal numbers, kept if in scope for a mode
        a, b, c = rnd(1, 2046), rnd(1, 2046), rnd(1, 2046)
        add(a, b, c)

    with open('fpr_fma_vectors.hex', 'w') as f:
        n = 0
        for a, b, c, op in v:
            rf, ru = ref_fused(a, b, c, op), ref_unfused(a, b, c, op)
            if rf == INVALID and ru == INVALID: continue
            f.write(f"{a:016x}{b:016x}{c:016x}{op:01x}{rf:016x}{ru:016x}\n")
            n += 1
    print(f"Wrote {n} vectors to fpr_fma_vectors.hex")

if __name__ == '__main__':
    main()
