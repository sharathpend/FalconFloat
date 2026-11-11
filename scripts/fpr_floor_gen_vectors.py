# Generates fpr_floor_vectors.hex for fpr_floor_tb.sv.
# Each line: <input double hex><expected int64 hex>
# Out-of-range inputs and NaN saturate by sign, matching fpr_floor.
import struct, math, random

random.seed(2)
M64 = (1 << 64) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m

def ref_floor(b):
    x = b2d(b)
    if math.isnan(x): return 0x8000000000000000 if b >> 63 else 0x7FFFFFFFFFFFFFFF
    if x >= 2.0**63:  return 0x7FFFFFFFFFFFFFFF
    if x < -2.0**63:  return 0x8000000000000000
    return math.floor(x) & M64

v = [0, 1 << 63, d2b(float('inf')), d2b(float('-inf')), 0x7FF8000000000000, 0xFFF8000000000000,
     1, (1 << 63) | 1, d2b(-2.0**63), d2b(2.0**63), d2b(-0.5), d2b(0.5), d2b(-1.0), d2b(1.0),
     d2b(-1.5), d2b(2.0**52 + 0.5)]
for e in range(1023 - 5, 1023 + 70):                 # every exponent around the int64 range
    for s in (0, 1):
        for m in (0, 1, (1 << 52) - 1, 1 << 51, (1 << 51) + 1):
            v.append(mkd(s, e, m))
        for _ in range(400):
            v.append(mkd(s, e, random.getrandbits(52)))
for _ in range(20000):                               # integers and near-integers
    n = random.getrandbits(random.randint(1, 62)) * random.choice([-1, 1])
    for d in (0.0, 0.25, -0.25, 0.5, -0.5):
        v.append(d2b(float(n) + d))
for _ in range(50000): v.append(random.getrandbits(64))

with open('fpr_floor_vectors.hex', 'w') as f:
    for b in v: f.write(f"{b:016x}{ref_floor(b):016x}\n")
print(f"Wrote {len(v)} vectors to fpr_floor_vectors.hex")
