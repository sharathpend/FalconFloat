
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_top_vectors.hex for fpr_top_tb.sv: a random mix of every fpr_top op.
# Each line: <op 2 hex><check mask 1 hex><a><b><c><out_tdata><out_tdata2><out_tdata3><out_tdata if FUSED=0>
#   (all 16 hex digits). Check mask: bit 0 out_tdata, bit 1 out_tdata2, bit 2 out_tdata3.
# The references are those of the unit generators (fpr_fma, fpr_to_int, fpr_div, ...);
# operands are drawn so every op stays in its unit's scope.
import math, random
from fpr_fma_gen_vectors import ref_fused, ref_unfused, d2b, b2d, mkd, ok, rnd, INVALID
from fpr_to_int_gen_vectors import ref as ref_to_int
from fpr_div_gen_vectors import ref as ref_div

M64 = (1 << 64) - 1
OPS = {'ADD': 0x00, 'SUB': 0x01, 'MUL': 0x02, 'FMA': 0x03, 'FMS': 0x04, 'FNMA': 0x05, 'FNMS': 0x06,
       'FLOOR': 0x08, 'CEIL': 0x09, 'TRUNC': 0x0A, 'ROUND': 0x0B, 'INT2FPR': 0x0C,
       'DIV': 0x10, 'INV': 0x11, 'SQRT': 0x12, 'INT64_MUL': 0x14, 'UINT64_MUL': 0x15}

def val():          # operand mix: mostly well in range, some zeros and wide exponents
    c = random.random()
    if c < 0.05: return random.choice([0, 1 << 63])
    if c < 0.75: return rnd(990, 1056)
    return rnd(800, 1250)

def one(name):
    op = OPS[name]
    a, b, c = val(), val(), val()
    if name in ('ADD', 'SUB'):
        r = b2d(a) + b2d(b) if name == 'ADD' else b2d(a) - b2d(b)
        return (op, 1, a, b, 0, d2b(r), 0, 0, d2b(r)) if ok(r) else None
    if name == 'MUL':
        r = ref_unfused(a, b, 1 << 63, 0)                # a * b + (-0) = fpr_mul(a, b)
        return (op, 1, a, b, 0, r, 0, 0, r) if r != INVALID else None
    if name in ('FMA', 'FMS', 'FNMA', 'FNMS'):
        k = op - 0x03
        if random.random() < 0.3:                        # some cancellation
            p = b2d(a) * b2d(b) * (-1 if k >> 1 else 1)
            c = (d2b(-p) ^ random.getrandbits(3)) ^ ((k & 1) << 63)
        rf, ru = ref_fused(a, b, c, k), ref_unfused(a, b, c, k)
        if rf == INVALID or ru == INVALID: return None
        return (op, 1, a, b, c, rf, 0, 0, ru)
    if name in ('FLOOR', 'CEIL', 'TRUNC', 'ROUND'):
        x = random.choice([rnd(1000, 1090), rnd(1, 1021), d2b(random.randint(-10**6, 10**6) + random.choice([0, 0.5, 0.25]))])
        i, d, r = ref_to_int(x, op - 0x08)
        return (op, 7, x, 0, 0, i, d, r, i)
    if name == 'INT2FPR':
        n = random.getrandbits(random.randint(1, 64))
        s = n - (1 << 64) if n >> 63 else n
        r = d2b(float(s))
        return (op, 1, n, 0, 0, r, 0, 0, r)
    if name == 'DIV':
        if b == 0 or b == 1 << 63: return None
        q = ref_div(a, b)
        return (op, 1, a, b, 0, q, 0, 0, q) if q is not None else None
    if name == 'INV':
        if a == 0 or a == 1 << 63: return None
        q = ref_div(d2b(1.0), a)
        return (op, 1, a, 0, 0, q, 0, 0, q) if q is not None else None
    if name == 'SQRT':
        a &= ~(1 << 63)
        if random.random() < 0.02: a |= 1 << 63 if a == 0 else 0
        r = d2b(math.sqrt(b2d(a)))
        return (op, 1, a, 0, 0, r, 0, 0, r)
    a, b = random.getrandbits(64), random.getrandbits(64)
    if name == 'INT64_MUL':
        p = (((a >> 63) ^ (b >> 63)) << 127) | (((a & (M64 >> 1)) * (b & (M64 >> 1))) & ((1 << 126) - 1))
    else:
        p = a * b
    return (op, 3, a, b, 0, p & M64, p >> 64, 0, p & M64)

def main():
    random.seed(80)
    names = list(OPS)
    lines = []
    while len(lines) < 200000:
        name = random.choice(names)
        for _ in range(random.choice([1, 1, 1, 4])):     # some runs of the same op
            t = one(name)
            if t: lines.append("%02x%01x" % t[:2] + "".join("%016x" % x for x in t[2:]) + "\n")
    for bad in (0x07, 0x0D, 0x13, 0x1F):                 # unused op codes (always out_error)
        lines.insert(random.randrange(len(lines)), "%02x0" % bad + "0" * 16 * 7 + "\n")
    with open('fpr_top_vectors.hex', 'w') as f: f.writelines(lines)
    print(f"Wrote {len(lines)} vectors to fpr_top_vectors.hex")

if __name__ == '__main__':
    main()
