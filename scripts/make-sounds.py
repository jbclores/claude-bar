#!/usr/bin/env python3
# ClaudeBar's cat sounds, generated from code: python3 scripts/make-sounds.py Resources/Sounds
# No recorded audio is used or read. The meow and ding are pure synthesis; the purr follows a few numbers
# measured from a public-domain (CC0) recording (BigSoundBank #0436): its tone by band, breath curve and tap
# timing/strength statistics. Those numbers are below; none of the recording is.
import math, random, struct, wave, sys

RATE = 44100

def write(path, samples, rate=RATE):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.85 * 32767)) for s in samples))

class Resonator:
    """A two-pole resonance (a formant) whose frequency and bandwidth can change every sample."""
    def __init__(self): self.y1 = self.y2 = 0.0
    def __call__(self, x, f, bw):
        r = math.exp(-math.pi * bw / RATE); c = 2 * r * math.cos(2 * math.pi * f / RATE)
        y = (1 - r) * x + c * self.y1 - r * r * self.y2
        self.y2, self.y1 = self.y1, y
        return y

def lerp(a, b, t): return a + (b - a) * t

def smooth(t): return t * t * (3 - 2 * t)

def track(points, t):
    """Piecewise-smooth value along (time, value) points, t in 0…1."""
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1: return lerp(v0, v1, smooth((t - t0) / (t1 - t0)))
    return points[-1][1]

def meow(dur=0.8, seed=3):
    random.seed(seed)
    n = int(RATE * dur)
    # A small cat: higher, tenser pitch; quick rise to a held peak, then a whiny fall ("nyaow").
    pitch = [(0, 560), (0.14, 920), (0.4, 1020), (0.72, 820), (1, 600)]
    # Cat-sized vocal tract: resonances well above a person's. "ny" → open "aa" → narrowed "ow".
    f1 = [(0, 500), (0.14, 1100), (0.45, 1250), (0.8, 950), (1, 750)]
    f2 = [(0, 2200), (0.14, 2800), (0.45, 2600), (0.8, 1900), (1, 1600)]
    f3 = [(0, 3800), (0.3, 4300), (1, 3900)]
    loud = [(0, 0), (0.05, 0.4), (0.15, 1), (0.7, 0.9), (0.92, 0.35), (1, 0)]
    r1, r2, r3, nasal, nasal2 = Resonator(), Resonator(), Resonator(), Resonator(), Resonator()
    out = []; phase = 0.0; jitter = 0.0; soft = 0.0; lp = 0.0
    for i in range(n):
        t = i / n
        jitter = 0.995 * jitter + 0.005 * random.gauss(0, 1)
        f0 = track(pitch, t) * (1 + 0.008 * jitter + 0.006 * math.sin(2 * math.pi * 6 * i / RATE))
        phase = (phase + f0 / RATE) % 1.0
        # Tense voice: a short open phase gives strong upper harmonics (bright, thin), little breath.
        g = 0.5 * (1 - math.cos(2 * math.pi * phase / 0.4)) if phase < 0.4 else 0.0
        src = (g - 0.2) * (1 + 0.03 * random.gauss(0, 1)) + 0.03 * random.uniform(-1, 1)
        # A little smoother: a mild softening of the voice's sharpest edge (keeps its brightness).
        soft = 0.45 * soft + 0.55 * src
        src = soft
        oral = r1(src, track(f1, t), 110) + 0.8 * r2(src, track(f2, t), 160) + 0.45 * r3(src, track(f3, t), 260)
        # Nasal twang all the way through, strongest at the start ("ny").
        twang = 0.55 * nasal(src, 1800, 90) + 0.35 * nasal2(src, 350, 70)
        start = min(1, t / 0.1)
        v = oral * (0.35 + 0.65 * start) + twang * (1.2 - 0.6 * start)
        lp = 0.3 * lp + 0.7 * v                                           # a very light high-cut
        out.append(lp * track(loud, t))
    return out

# A purr's tone by pitch band (dB below its loudest), its breath curve, and how uneven its taps are: measured from
# a public-domain recording (BigSoundBank #0436, CC0). Only these numbers are used; none of its audio.
PURR_TONE_DB = [(60, -17.0), (67, -7.3), (75, -2.8), (84, -9.3), (94, -7.0), (106, -6.7), (118, -3.8), (133, -7.0), (148, -6.4), (166, -2.5), (186, -0.9), (208, -1.4), (233, 0.0), (261, -3.0), (293, -7.0), (328, -9.2), (367, -10.1), (411, -10.9), (461, -11.3), (516, -15.5), (578, -22.7), (647, -31.2), (724, -30.0), (811, -23.6), (908, -23.5), (1017, -21.4), (1139, -20.7), (1276, -23.9), (1429, -25.5), (1600, -28.6)]
PURR_BREATH = [0.83, 0.75, 0.69, 0.66, 0.7, 0.74, 0.68, 0.65, 0.8, 0.91, 0.9, 0.82, 0.76, 0.86, 0.84, 0.78, 0.86, 0.97, 1.0, 0.92]
PURR_TAP_MS, PURR_TAP_SD_MS, PURR_STRENGTH_SD = 40.0, 3.3, 0.45
PURR_RATE = 11025      # a purr has nothing above ~1.6 kHz

def purr_filter(taps=511):
    """A linear-phase filter whose response follows PURR_TONE_DB (frequency sampling)."""
    def db_at(f):
        if f <= PURR_TONE_DB[0][0]: return PURR_TONE_DB[0][1] - 12 * math.log2(PURR_TONE_DB[0][0] / max(f, 1))
        if f >= PURR_TONE_DB[-1][0]: return PURR_TONE_DB[-1][1] - 12 * math.log2(f / PURR_TONE_DB[-1][0])
        for (f0, d0), (f1, d1) in zip(PURR_TONE_DB, PURR_TONE_DB[1:]):
            if f <= f1:
                t = math.log(f / f0) / math.log(f1 / f0); return d0 + (d1 - d0) * t
    N = 2048; mid = (taps - 1) / 2
    mags = [10 ** (db_at(k * PURR_RATE / N) / 20) for k in range(N // 2 + 1)]
    h = []
    for j in range(taps):
        acc = mags[0] + sum(2 * mags[k] * math.cos(2 * math.pi * k * (j - mid) / N) for k in range(1, N // 2))
        win = 0.5 - 0.5 * math.cos(2 * math.pi * j / (taps - 1))
        h.append(acc / N * win)
    return h

def purr(dur=2.4, seed=5):
    random.seed(seed)
    n = int(PURR_RATE * dur)
    exc = [0.0] * n
    t = 0.0
    while t < dur:
        at = int(t * PURR_RATE)
        k = max(0.15, random.lognormvariate(0, PURR_STRENGTH_SD * 0.93))   # uneven tap strengths, as measured
        for j, w in enumerate((0.25, 1.0, 0.25)):                          # a tiny smooth pulse
            if 0 <= at + j < n: exc[at + j] += k * w
        t += max(0.025, random.gauss(PURR_TAP_MS, PURR_TAP_SD_MS) / 1000)  # uneven timing, as measured
    h = purr_filter()
    y = [0.0] * n
    nz = [(i, v) for i, v in enumerate(exc) if v]
    for i, v in nz:
        for j, c in enumerate(h):
            if i + j < n: y[i + j] += v * c
    # Breath: the measured curve over ~1.46 s, each breath a little different; ends faded.
    out = []; period = 1.46; wobble = [1 + random.gauss(0, 0.05) for _ in range(8)]
    for i in range(n):
        tt = i / PURR_RATE; ph = (tt % period) / period * len(PURR_BREATH)
        a, b = PURR_BREATH[int(ph) % len(PURR_BREATH)], PURR_BREATH[(int(ph) + 1) % len(PURR_BREATH)]
        breath = (a + (b - a) * (ph - int(ph))) * wobble[int(tt / period) % 8]
        fade = min(1, tt / 0.15, (dur - tt) / 0.3)
        out.append(y[i] * breath * fade)
    return out

def ding(dur=1.2):
    n = int(RATE * dur); out = []
    for i in range(n):
        t = i / RATE
        v = (math.sin(2 * math.pi * 1318 * t) * math.exp(-t * 3.2)
             + 0.45 * math.sin(2 * math.pi * 2637 * t) * math.exp(-t * 5)
             + 0.25 * math.sin(2 * math.pi * 3951 * t) * math.exp(-t * 7))
        out.append(v * min(1, t / 0.004))
    return out

out = sys.argv[1] if len(sys.argv) > 1 else "."
write(f"{out}/meow.wav", meow()); write(f"{out}/purr.wav", purr(), PURR_RATE); write(f"{out}/ding.wav", ding())
print("wrote meow.wav, purr.wav, ding.wav")
