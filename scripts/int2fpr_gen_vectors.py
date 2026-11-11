# Generates int2fpr_vectors.hex for int2fpr_tb.sv.
# Each line: <64-bit input hex><64-bit expected double hex>
# Expected values come from Python's float(), which is IEEE-754 round-to-nearest-even.
import struct, random

random.seed(1)
M64 = (1 << 64) - 1
NUM_RANDOM = 200000

def ref(x):
    return struct.unpack('>Q', struct.pack('>d', float(x)))[0]

v = [0, 1, -1, 2, -2, 3, -3, 5, 100, -100, (1 << 63) - 1, -(1 << 63), -(1 << 63) + 1]

# Powers of two and their neighbours, both signs
for k in range(64):
    for d in (-1, 0, 1):
        x = (1 << k) + d
        v += [x, -x]

# Ties, near-ties and rounding carry-out for every width that needs rounding
for k in range(53, 63):
    sh = k - 52
    for base in (1 << 52, (1 << 52) + 1, (1 << 53) - 1, (1 << 53) - 2):
        for low in (1 << (sh - 1), (1 << (sh - 1)) - 1, (1 << (sh - 1)) + 1, 0, (1 << sh) - 1):
            if 0 <= low < (1 << sh):
                x = (base << sh) | low
                v += [x, -x]

# Random values spread across all bit-widths
for _ in range(NUM_RANDOM):
    x = random.getrandbits(random.randint(1, 64))
    v.append(x - (1 << 64) if x >= (1 << 63) else x)

v = [x for x in v if -(1 << 63) <= x < (1 << 63)]
with open('int2fpr_vectors.hex', 'w') as f:
    for x in v:
        f.write(f"{x & M64:016x}{ref(x):016x}\n")
print(f"Wrote {len(v)} vectors to int2fpr_vectors.hex")
