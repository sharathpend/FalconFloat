# Generates fpr_add_vectors.hex for fpr_add_tb.sv.
# Each line: <in1 hex><in2 hex><expected hex>, 16 hex chars each.
# Reference is Python's IEEE-754 double add (round-to-nearest-even).
# Vectors are restricted to FALCON's domain: inputs are +/-0 or normal numbers and
# the result is zero or normal. Inf, NaN, subnormals and overflow/underflow are
# excluded, because fpr_add does not handle them.
import struct, math, random

random.seed(3)
M52 = (1 << 52) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m          # e = biased exponent

def in_domain(x):          # +/-0 or a normal number
    e = (x >> 52) & 0x7FF
    return (x & ~(1 << 63)) == 0 or 1 <= e <= 2046

def ref_add(a, b):
    """Expected sum, or None if the result would be Inf or subnormal."""
    r = b2d(a) + b2d(b)
    if math.isinf(r) or (r != 0 and abs(r) < 2.0**-1022): return None
    return d2b(r)

def rnd(lo=1013, hi=1033): return mkd(random.getrandbits(1), random.randint(lo, hi), random.getrandbits(52))

v = []
for _ in range(20000): v.append((rnd(), rnd()))                                    # similar magnitudes
for _ in range(20000): v.append((d2b(random.uniform(-1e10, 1e10)), d2b(random.uniform(-1e10, 1e10))))
for _ in range(40000):                                                              # every exponent gap, both signs
    a = rnd(); d = random.randint(0, 60)
    v.append((a, mkd(random.getrandbits(1), ((a >> 52) & 0x7FF) - d, random.getrandbits(52))))
for _ in range(20000):                                                              # near-cancellation
    a = rnd(); ea = (a >> 52) & 0x7FF
    if random.getrandbits(1):
        b = mkd((a >> 63) ^ 1, ea, (a & M52) ^ random.getrandbits(random.randint(1, 20)))
    else:
        b = mkd((a >> 63) ^ 1, ea - 1, random.getrandbits(52) | (M52 & ~((1 << 20) - 1)))
    v.append((a, b))
for _ in range(40000):                                                              # alignment-boundary gaps, tie patterns
    ea = random.randint(60, 2045); d = random.choice([1, 2, 3, 4, 52, 53, 54, 55, 56, 57, 58])
    v.append((mkd(random.getrandbits(1), ea, random.choice([0, M52, 1, random.getrandbits(52)])),
              mkd(random.getrandbits(1), ea - d, random.choice([0, M52, 1, 1 << 51, (1 << 51) | 1, random.getrandbits(52)]))))
for _ in range(10000):                                                              # rounding carry-out
    e = random.randint(2, 2046)
    v.append((mkd(0, e, M52 ^ random.getrandbits(random.randint(0, 4))), mkd(0, e - random.choice([0, 1]), random.getrandbits(52))))
for _ in range(10000):                                                              # near overflow
    v.append((mkd(random.getrandbits(1), 2046 - random.randint(0, 2), random.getrandbits(52)),
              mkd(random.getrandbits(1), 2046 - random.randint(0, 60), random.getrandbits(52))))
for _ in range(10000):                                                              # near underflow
    e = random.randint(2, 60); m = random.getrandbits(52)
    v.append((mkd(0, e, m), mkd(1, e - random.choice([0, 1]), m ^ random.getrandbits(random.randint(1, 52)))))
for _ in range(50000): v.append((random.getrandbits(64), random.getrandbits(64)))   # any bit pattern
sp = [0, 1 << 63, d2b(1.0), d2b(-1.0), d2b(0.5), d2b(-3.75), d2b(1.7e308), d2b(-1.7e308), d2b(2.2250738585072014e-308)]
v += [(x, y) for x in sp for y in sp]                                               # zeros and extremes

n = 0
with open('fpr_add_vectors.hex', 'w') as f:
    for a, b in v:
        if not (in_domain(a) and in_domain(b)): continue
        e = ref_add(a, b)
        if e is None: continue
        f.write(f"{a:016x}{b:016x}{e:016x}\n"); n += 1
print(f"Wrote {n} vectors to fpr_add_vectors.hex")
