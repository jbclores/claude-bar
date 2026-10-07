#!/usr/bin/env python3
# ClaudeBar's office lofi loop, generated from code (no samples or recordings): python3 scripts/make-music.py Resources/Sounds
# Python standard library only.
import math, random, struct, wave, sys

RATE = 22050
BPM = 72
BEAT = 60 / BPM
BAR = 4 * BEAT
random.seed(11)

def note_hz(n): return 440 * 2 ** ((n - 69) / 12)    # MIDI note number → Hz

# ii9 – V13 – Imaj9 – vi9 in C, a classic lofi turn (MIDI notes, voiced around middle C).
CHORDS = [
    ([62, 65, 69, 72, 76], 38),   # Dm9:  D F A C E, bass D
    ([59, 65, 69, 71, 76], 43),   # G13:  B F A B E, bass G
    ([60, 64, 67, 71, 74], 36),   # Cmaj9: C E G B D, bass C
    ([60, 64, 67, 69, 71], 45),   # Am9:  C E G A B, bass A
]

def render(bars=16):
    loop = int(RATE * BAR * bars)
    n = loop + int(RATE * BAR * 2)          # a tail for notes still ringing at the end
    mix = [0.0] * n

    def add(at, samples, gain=1.0):
        i0 = int(at * RATE)
        for j, v in enumerate(samples):
            if 0 <= i0 + j < n: mix[i0 + j] += v * gain

    wobble = lambda t: 1 + 0.003 * math.sin(2 * math.pi * 0.45 * t) + 0.0015 * math.sin(2 * math.pi * 1.7 * t)

    def ep_note(hz, start, dur, vel):
        """Electric-piano-like tone: soft bell attack, warm harmonics, slow decay, a little tremolo."""
        out = []; ph = 0.0
        for j in range(int(RATE * dur)):
            t = j / RATE
            ph += 2 * math.pi * hz * wobble(start + t) / RATE
            env = (1 - math.exp(-t * 60)) * math.exp(-t * 1.1)
            trem = 1 + 0.12 * math.sin(2 * math.pi * 4.2 * t)
            tone = math.sin(ph) + 0.28 * math.sin(2 * ph) * math.exp(-t * 3) + 0.08 * math.sin(3 * ph) * math.exp(-t * 6)
            out.append(vel * env * trem * tone)
        return out

    def bass_note(hz, start, dur, vel):
        out = []; ph = 0.0
        for j in range(int(RATE * dur)):
            t = j / RATE
            ph += 2 * math.pi * hz * wobble(start + t) / RATE
            env = (1 - math.exp(-t * 80)) * math.exp(-t * 1.6)
            out.append(vel * env * math.tanh(1.6 * math.sin(ph)))
        return out

    def kick(vel):
        out = []; ph = 0.0
        for j in range(int(RATE * 0.35)):
            t = j / RATE; f = 50 + 80 * math.exp(-t * 28)
            ph += 2 * math.pi * f / RATE
            out.append(vel * math.exp(-t * 9) * math.sin(ph))
        return out

    def snare(vel):
        out = []; lp = 0.0; ph = 0.0
        for j in range(int(RATE * 0.22)):
            t = j / RATE
            lp = 0.6 * lp + 0.4 * random.uniform(-1, 1)          # brushy: softened noise
            ph += 2 * math.pi * 185 / RATE
            out.append(vel * (0.7 * lp * math.exp(-t * 16) + 0.3 * math.sin(ph) * math.exp(-t * 30)))
        return out

    def hat(vel):
        out = []; prev = 0.0
        for j in range(int(RATE * 0.05)):
            t = j / RATE; x = random.uniform(-1, 1)
            out.append(vel * (x - prev) * math.exp(-t * 90)); prev = x
        return out

    swing = 0.62   # the off-beat eighth lands late: a lazy swing
    for b in range(bars + 1):               # one extra bar's start rings into the tail, as the loop's next bar would
        notes, root = CHORDS[b % len(CHORDS)]
        t0 = b * BAR
        # Chords: a soft hit on beat 1 and a lighter one on the swung "and" of 2.
        for at, vel in ((0.0, 0.12), (BEAT * (1 + swing), 0.07)):
            for k, m in enumerate(notes):
                add(t0 + at + 0.012 * k, ep_note(note_hz(m), t0 + at, BAR - at + 0.6, vel * (1 - 0.06 * k)))
        # Bass: root on 1, a step on the swung "and" of 3, back to the root.
        for at, m, d in ((0.0, root, BEAT * 2.2), (BEAT * (2 + swing), root + 7, BEAT * 0.9), (BEAT * 3.5, root, BEAT * 0.6)):
            add(t0 + at, bass_note(note_hz(m), t0 + at, d, 0.32))
        # Drums: kick on 1 and the "and" of 3 (sometimes 3), brushy snare on 2 and 4, soft swung hats.
        add(t0, kick(0.55)); add(t0 + BEAT * (2 + swing), kick(0.4 if b % 2 else 0.0)); add(t0 + BEAT * 2, kick(0.35 if b % 2 == 0 else 0.0))
        for beat in (1, 3): add(t0 + beat * BEAT + random.uniform(0, 0.01), snare(0.22))
        for e in range(8):
            at = (e // 2) * BEAT + (swing * BEAT if e % 2 else 0)
            add(t0 + at + random.uniform(-0.006, 0.006), hat(0.08 if e % 2 else 0.12))

    # Vinyl: a faint hiss and the odd crackle. Master: warm low-pass and gentle saturation.
    out = []; lp1 = lp2 = 0.0
    for i in range(n):
        crackle = random.uniform(-1, 1) * 0.35 if random.random() < 9 / RATE else 0.0
        x = mix[i] + 0.004 * random.uniform(-1, 1) + crackle * 0.06
        lp1 = 0.72 * lp1 + 0.28 * x; lp2 = 0.72 * lp2 + 0.28 * lp1          # roll off the top (~3-4 kHz)
        out.append(math.tanh(1.3 * lp2))
    # Fold the tail back onto the start: the loop joins without a gap or a click.
    for j in range(n - loop): out[j] = math.tanh(out[j] + out[loop + j])
    return out[:loop]

def write(path, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.8 * 32767)) for s in samples))

out = sys.argv[1] if len(sys.argv) > 1 else "."
bars = int(sys.argv[2]) if len(sys.argv) > 2 else 16
write(f"{out}/office-lofi.wav", render(bars))
print(f"wrote office-lofi.wav ({bars} bars, {bars * BAR:.1f} s)")
