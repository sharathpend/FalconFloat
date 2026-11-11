# Generates fpr_round_vectors.hex for fpr_round_tb.sv.
# Each line: <input double hex><expected int64 hex>
# Reference: Python round() on a float (round to nearest, ties to even).
# |x| >= 2^63 saturates by sign (-2^63 itself is exact). Inputs are +/-0 or normal.
import struct, random

random.seed(11)
M64 = (1 << 64) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m

def ref_round(b):
    x = b2d(b)
    if x >= 2.0**63: return 0x7FFFFFFFFFFFFFFF
    if x < -2.0**63: return 0x8000000000000000
    return round(x) & M64

v = [0, 1 << 63, d2b(0.5), d2b(-0.5), d2b(1.5), d2b(-1.5), d2b(2.5), d2b(-2.5), d2b(0.49999999999999994),
     d2b(-0.49999999999999994), d2b(2.0**52 + 1), d2b(2.0**52 - 0.5), d2b(2.0**53 - 1), d2b(-2.0**63),
     d2b(2.0**63), d2b(9.2233720368547748e18), d2b(-9.223372036854777e18), d2b(1e-300), d2b(-1e-300)]
for e in range(1023 - 8, 1023 + 66):                  # every exponent around the int64 range
    for s in (0, 1):
        for m in (0, 1, (1 << 52) - 1, 1 << 51, (1 << 51) + 1, (1 << 51) - 1):
            v.append(mkd(s, e, m))
        for _ in range(500):
            v.append(mkd(s, e, random.getrandbits(52)))
for _ in range(30000):                                # exact ties and near-ties around integers
    n = random.getrandbits(random.randint(1, 51)) * random.choice([-1, 1])
    for d in (0.5, -0.5, 0.25, 0.75, 0.0):
        v.append(d2b(float(n) + d))
    x = float(n) + 0.5
    v.append(d2b(x) + 1); v.append(d2b(x) - 1)       # one ulp either side of the tie
for _ in range(30000):                                # any normal number
    v.append(mkd(random.getrandbits(1), random.randint(1, 2046), random.getrandbits(52)))

with open('fpr_round_vectors.hex', 'w') as f:
    for b in v: f.write(f"{b:016x}{ref_round(b):016x}\n")
print(f"Wrote {len(v)} vectors to fpr_round_vectors.hex")
