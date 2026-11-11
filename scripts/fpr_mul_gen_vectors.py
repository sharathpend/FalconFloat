# Generates fpr_mul_vectors.hex for fpr_mul_tb.sv.
# Each line: <in1 hex><in2 hex><expected hex>, 16 hex chars each.
# Reference: exact integer product, round-to-nearest-even.
# Vectors are restricted to FALCON's domain: inputs are +/-0 or normal numbers and
# the result is zero or normal. Inf, NaN, subnormals and overflow/underflow are
# excluded, because fpr_mul does not handle them.
import struct, random

random.seed(5)
M52 = (1 << 52) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m          # e = biased exponent

def in_domain(x):          # +/-0 or a normal number
    e = (x >> 52) & 0x7FF
    return (x & ~(1 << 63)) == 0 or 1 <= e <= 2046

def ref_mul(a, b):
    """Expected product, or None if the result would overflow or underflow."""
    sa, ea, ma = a >> 63, (a >> 52) & 0x7FF, a & M52
    sb, eb, mb = b >> 63, (b >> 52) & 0x7FF, b & M52
    s = sa ^ sb
    if ea == 0 or eb == 0: return s << 63                    # a zero operand
    P = ((1 << 52) | ma) * ((1 << 52) | mb)
    e, sh = ea + eb - 1023, 52
    if P >> 105: e, sh = e + 1, 53
    m, rem, half = P >> sh, P & ((1 << sh) - 1), 1 << (sh - 1)
    if rem > half or (rem == half and (m & 1)): m += 1
    if m >> 53: m, e = m >> 1, e + 1
    if e >= 2047 or e <= 0: return None                     # out of scope
    return (s << 63) | (e << 52) | (m & M52)

def rn(lo=900, hi=1150): return mkd(random.getrandbits(1), random.randint(lo, hi), random.getrandbits(52))

v = []
for _ in range(30000): v.append((rn(), rn()))                                       # moderate exponents
for _ in range(30000):                                                              # like fpr.py's test
    v.append((d2b(random.uniform(1e-100, 1e100) * random.choice([-1, 1])),
              d2b(random.uniform(1e-100, 1e100) * random.choice([-1, 1]))))
for _ in range(10000):                                                              # rounding carry-out
    k = random.randint(1, 26)
    v.append((mkd(random.getrandbits(1), random.randint(900, 1100), M52 ^ random.getrandbits(k)),
              mkd(random.getrandbits(1), random.randint(900, 1100), random.getrandbits(random.randint(0, k)))))
for _ in range(10000):                                                              # exact ties (G=1, S=0) and near-ties
    lo = random.randint(1, 26)
    v.append((mkd(random.getrandbits(1), random.randint(900, 1100), random.getrandbits(52 - lo) << lo),
              mkd(random.getrandbits(1), random.randint(900, 1100), random.getrandbits(lo) << (52 - lo))))
for _ in range(5000):                                                               # a zero operand
    z, x = random.choice([0, 1 << 63]), rn()
    v.append((z, x) if random.getrandbits(1) else (x, z))
for _ in range(10000):                                                              # around the overflow threshold
    e1 = random.randint(1024, 2046)
    v.append((mkd(random.getrandbits(1), e1, random.getrandbits(52)),
              mkd(random.getrandbits(1), 3069 - e1 + random.randint(-2, 1), random.choice([M52, M52 - 1, random.getrandbits(52)]))))
for _ in range(10000):                                                              # around the underflow threshold
    e1 = random.randint(1, 1022)
    v.append((mkd(random.getrandbits(1), e1, random.choice([M52, M52 ^ random.getrandbits(8), random.getrandbits(52)])),
              mkd(random.getrandbits(1), 1023 - e1 + random.randint(-1, 2), random.choice([M52, M52 ^ random.getrandbits(8), random.getrandbits(52)]))))
for _ in range(50000): v.append((random.getrandbits(64), random.getrandbits(64)))   # any bit pattern
sp = [0, 1 << 63, d2b(1.0), d2b(-2.5), d2b(0.5), d2b(1.7e308), d2b(2.2250738585072014e-308)]
v += [(x, y) for x in sp for y in sp]                                               # zeros and extremes

n = 0
with open('fpr_mul_vectors.hex', 'w') as f:
    for a, b in v:
        if not (in_domain(a) and in_domain(b)): continue
        e = ref_mul(a, b)
        if e is None: continue
        f.write(f"{a:016x}{b:016x}{e:016x}\n"); n += 1
print(f"Wrote {n} vectors to fpr_mul_vectors.hex")
