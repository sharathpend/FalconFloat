
# Disclaimer: This project is provided "AS IS" without warranty for personal,
# educational, and research use. See the LICENSE file for the full terms and
# restrictions, including non-commercial use conditions.

# Generates fpr_butterfly_vectors.hex for fpr_butterfly_tb.sv.
# Each line: <mode 1 hex><conj_s 1 hex><x_re><x_im><y_re><y_im><s_re><s_im>
#            <x'_re><x'_im><y'_re><y'_im> for FUSED=0, then the same 4 for FUSED=1
# (all doubles as 16 hex digits).
#   mode 0 (FFT):  t = y * s;  x' = x + t;  y' = x - t
#   mode 1 (iFFT): x' = x + y;  y' = (x - y) * s
#   conj_s = 1 uses conj(s).
# FUSED=0 follows FALCON's FPC_MUL / FPC_ADD / FPC_SUB exactly:
#   (p * s).re = fl(fl(p_re*s_re) - fl(p_im*s_im)),  .im = fl(fl(p_re*s_im) + fl(p_im*s_re))
# FUSED=1: .re = round(p_re*s_re - fl(p_im*s_im)),  .im = round(p_im*s_re + fl(p_re*s_im)).
# Lines come in runs of one mode, so the testbench also sees mode changes.
# A line whose expected values hold ffffffffffffffff is out of scope for that mode.
import math, random
from fpr_fma_gen_vectors import ref_fused, d2b, b2d, mkd, ok, rnd, INVALID

random.seed(40)
NEG = 1 << 63

class OutOfScope(Exception): pass

def chk(b):
    if not ok(b2d(b)): raise OutOfScope
    return b

def fadd(a, b): return chk(d2b(b2d(a) + b2d(b)))
def fsub(a, b): return chk(d2b(b2d(a) - b2d(b)))
def fmul(a, b):
    r = b2d(a) * b2d(b)
    if r == 0 and b2d(a) != 0 and b2d(b) != 0: raise OutOfScope
    return chk(d2b(r))

def cmul(p_re, p_im, s_re, s_im, fused):
    m1, m2 = fmul(p_im, s_im), fmul(p_re, s_im)
    if fused:
        re, im = ref_fused(p_re, s_re, m1, 1), ref_fused(p_im, s_re, m2, 0)
        if re == INVALID or im == INVALID: raise OutOfScope
        return re, im
    return fsub(fmul(p_re, s_re), m1), fadd(fmul(p_im, s_re), m2)

def ref(mode, conj, x_re, x_im, y_re, y_im, s_re, s_im, fused):
    if conj: s_im ^= NEG
    try:
        if mode == 0:
            t_re, t_im = cmul(y_re, y_im, s_re, s_im, fused)
            return [fadd(x_re, t_re), fadd(x_im, t_im), fsub(x_re, t_re), fsub(x_im, t_im)]
        u_re, u_im = fsub(x_re, y_re), fsub(x_im, y_im)
        return [fadd(x_re, y_re), fadd(x_im, y_im)] + list(cmul(u_re, u_im, s_re, s_im, fused))
    except OutOfScope:
        return [INVALID] * 4

def gauss(): return d2b(random.gauss(0, 1) * 2.0 ** random.randint(-20, 20))
def twiddle():
    k = random.randrange(2048)
    return d2b(math.cos(math.pi * k / 1024)), d2b(math.sin(math.pi * k / 1024))
special_s = [(d2b(1.0), 0), (0, d2b(1.0)), (d2b(-1.0), 0), (0, d2b(-1.0)), (d2b(math.sqrt(0.5)), d2b(math.sqrt(0.5)))]

def one():
    c = random.random()
    if c < 0.5:                                          # FFT-like data and unit twiddles
        x_re, x_im, y_re, y_im = gauss(), gauss(), gauss(), gauss()
        s_re, s_im = twiddle()
    elif c < 0.75:                                       # any normal values, any s
        x_re, x_im, y_re, y_im, s_re, s_im = (rnd(1000, 1046) for _ in range(6))
    elif c < 0.85:                                       # special twiddles, zeros
        x_re, x_im, y_re, y_im = (random.choice([0, NEG, gauss()]) for _ in range(4))
        s_re, s_im = random.choice(special_s + [twiddle()])
    else:                                                # cancellation: x = +/-y, or x = -/+ y*s
        y_re, y_im = gauss(), gauss()
        s_re, s_im = twiddle()
        if random.random() < 0.5:
            x_re, x_im = (y_re, y_im) if random.random() < 0.5 else (y_re ^ NEG, y_im ^ NEG)
        else:
            t = b2d(y_re) * b2d(s_re) - b2d(y_im) * b2d(s_im), b2d(y_re) * b2d(s_im) + b2d(y_im) * b2d(s_re)
            x_re, x_im = d2b(-t[0]) ^ random.getrandbits(2), d2b(-t[1]) ^ random.getrandbits(2)
    return x_re, x_im, y_re, y_im, s_re, s_im

lines = []
while len(lines) < 120000:
    mode = random.getrandbits(1)
    for _ in range(random.randint(1, 64)):
        conj = random.getrandbits(1)
        v = one()
        e0, e1 = ref(mode, conj, *v, False), ref(mode, conj, *v, True)
        if e0[0] == INVALID and e1[0] == INVALID: continue
        lines.append(f"{mode:01x}{conj:01x}" + "".join(f"{b:016x}" for b in list(v) + e0 + e1) + "\n")

with open('fpr_butterfly_vectors.hex', 'w') as f: f.writelines(lines)
print(f"Wrote {len(lines)} vectors to fpr_butterfly_vectors.hex")
