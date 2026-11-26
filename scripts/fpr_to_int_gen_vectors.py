
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_to_int_vectors.hex for fpr_to_int_tb.sv.
# Each line: <mode 1 hex><check mask 1 hex><x hex><expected int64 hex><expected double hex><expected residue hex>
#   mode: 0 floor, 1 ceil, 2 trunc, 3 round (nearest, ties to even)
#   check mask: bit 0 int64, bit 1 double, bit 2 residue (always 7 here)
# Reference: n = floor / ceil / trunc / round_half_even(x) exactly, int64 = n,
#   double = float(n) (= fpr_of(n)), residue = x - float(n) in IEEE double (RNE).
# |x| >= 2^63, Inf and NaN: int64 saturates by sign, double = x, residue = +0.
import math, random, struct

M64 = (1 << 64) - 1
M52 = (1 << 52) - 1

def d2b(f): return struct.unpack('>Q', struct.pack('>d', f))[0]
def b2d(b): return struct.unpack('>d', struct.pack('>Q', b))[0]
def mkd(s, e, m): return (s << 63) | (e << 52) | m

ROUNDERS = [math.floor, math.ceil, math.trunc, round]   # round() on a float is ties-to-even

def ref(b, mode):
    x = b2d(b)
    if math.isnan(x) or x >= 2.0**63 or x < -2.0**63:
        return (0x8000000000000000 if b >> 63 else 0x7FFFFFFFFFFFFFFF), b, 0
    n = ROUNDERS[mode](x)
    return n & M64, d2b(float(n)), d2b(x - float(n))

def main():
    random.seed(70)
    xs = [0, 1 << 63, 1, (1 << 63) | 1, M52, (1 << 63) | M52, d2b(float('inf')), d2b(float('-inf')),
          0x7FF8000000000000, 0xFFF8000000000000, d2b(-2.0**63), d2b(2.0**63), d2b(2.0**63 - 1024)]
    for h in (0.5, 1.5, 2.5, 3.5, -0.5, -1.5, -2.5, -3.5, 0.49999999999999994, -0.49999999999999994,
              2.0**52 + 1, -(2.0**52) - 1, 2.0**52 - 0.5, -(2.0**52) + 0.5, 2.0**-60, -2.0**-60, 1e-300, -1e-300):
        xs.append(d2b(h))
    for e in range(0, 1023 + 66):                        # every exponent from subnormal up past 2^63
        reps = 60 if e >= 1023 - 70 else 2
        for s in (0, 1):
            for m in (0, 1, M52, 1 << 51, (1 << 51) + 1):
                xs.append(mkd(s, e, m))
            for _ in range(reps):
                xs.append(mkd(s, e, random.getrandbits(52)))
    for _ in range(10000):                               # integers, halves and near-integers
        n = random.getrandbits(random.randint(1, 52)) * random.choice([-1, 1])
        for d in (0.0, 0.5, -0.5, 0.25, -0.25, 2.0**-30):
            xs.append(d2b(float(n) + d))
    for _ in range(10000):                               # |x| < 0.5: the rounded residue path
        xs.append(mkd(random.getrandbits(1), random.randint(900, 1021), random.getrandbits(52)))
        xs.append(mkd(random.getrandbits(1), random.randint(1021 - 60, 1021), M52 - random.getrandbits(random.randint(0, 6))))
    for _ in range(10000):                               # anything, including subnormals, Inf and NaN
        xs.append(random.getrandbits(64))
    with open('fpr_to_int_vectors.hex', 'w') as f:
        n = 0
        for b in xs:
            for mode in range(4):
                i, d, r = ref(b, mode)
                f.write(f"{mode:01x}7{b:016x}{i:016x}{d:016x}{r:016x}\n")
                n += 1
    print(f"Wrote {n} vectors to fpr_to_int_vectors.hex")

if __name__ == '__main__':
    main()
