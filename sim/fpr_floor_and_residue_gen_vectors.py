# Generates fpr_floor_and_residue_vectors.hex for fpr_floor_and_residue_tb.sv.
# Each line: <input double hex><expected floor int64 hex><expected residue double hex>
# Reference matches FALCON's  s = fpr_floor(x); r = fpr_sub(x, fpr_of(s)):
#   floor = math.floor(x), residue = x - float(floor) in IEEE double (round to nearest even).
# float(floor) is exact here: for |x| >= 2^52 x is already an integer.
# |x| >= 2^63: floor saturates by sign and the residue is +0. Inputs are +/-0 or normal.
import struct, math, random

random.seed(12)
M64 = (1 << 64) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m

def ref(b):
    x = b2d(b)
    if x >= 2.0**63:  return 0x7FFFFFFFFFFFFFFF, 0
    if x < -2.0**63:  return 0x8000000000000000, 0
    fl = math.floor(x)
    return fl & M64, d2b(x - float(fl))

v = [0, 1 << 63, d2b(0.5), d2b(-0.5), d2b(1.0), d2b(-1.0), d2b(-1.5), d2b(-2.0**-60), d2b(-2.0**-54),
     d2b(-2.0**-53), d2b(-2.0**-55), d2b(-0.49999999999999994), d2b(-2.0**63), d2b(2.0**63),
     d2b(2.0**52 + 1), d2b(-(2.0**52) - 1), d2b(-(2.0**52) + 0.5), d2b(1e-300), d2b(-1e-300)]
for e in range(1, 1023 + 66, 1):                       # every exponent from tiny up past 2^63
    reps = 400 if e >= 1023 - 70 else 6
    for s in (0, 1):
        for m in (0, 1, (1 << 52) - 1, 1 << 51, (1 << 51) + 1):
            v.append(mkd(s, e, m))
        for _ in range(reps):
            v.append(mkd(s, e, random.getrandbits(52)))
for _ in range(30000):                                 # integers and near-integers
    n = random.getrandbits(random.randint(1, 51)) * random.choice([-1, 1])
    for d in (0.0, 0.5, -0.5, 0.25, 2.0**-30):
        v.append(d2b(float(n) + d))
for _ in range(30000):                                 # -0.5 < x < 0: the case that needs rounding
    v.append(mkd(1, random.randint(900, 1021), random.getrandbits(52)))
    v.append(mkd(1, random.randint(1021 - 60, 1021), (1 << 52) - 1 - random.getrandbits(random.randint(0, 6))))
for _ in range(30000):                                 # any normal number
    v.append(mkd(random.getrandbits(1), random.randint(1, 2046), random.getrandbits(52)))

with open('fpr_floor_and_residue_vectors.hex', 'w') as f:
    for b in v:
        fl, r = ref(b)
        f.write(f"{b:016x}{fl:016x}{r:016x}\n")
print(f"Wrote {len(v)} vectors to fpr_floor_and_residue_vectors.hex")
