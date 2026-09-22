#!/usr/bin/env python3
"""Synthesize the Swamp Club notification sounds for herdr.

swamp-club.com ships no audio, so these are original: short arcade blips
with a nod to Frogger's hop -- a square-wave chirp swept sharply upward, as
an early-80s sound chip would play it. "done" is the frog making it home;
"needs attention" is a hop that gets squashed, in the site's cyan/magenta
glitch. No Frogger audio or music is used. Standard library only; lame
encodes the mp3.

    python3 sounds/make-sounds.py      # writes sounds/done.mp3, sounds/request.mp3
"""
import math
import pathlib
import random
import struct
import subprocess
import tempfile
import wave

RATE = 44100
PEAK = 0.3  # about -10 dBFS: a nudge, not an alarm
HERE = pathlib.Path(__file__).resolve().parent


def tone(freq, dur, wave_mix=0.35, attack=0.004, release=0.06, bend=0.0):
    """A soft square/sine blend with an exponential tail.

    wave_mix 0 is a pure sine, 1 a pure square. bend is the pitch
    change in semitones across the note.
    """
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = freq * 2 ** (bend * (t / dur) / 12)
        phase += 2 * math.pi * f / RATE
        s = math.sin(phase)
        sq = 1.0 if s >= 0 else -1.0
        env = min(1.0, t / attack) * math.exp(-t / release)
        out.append(((1 - wave_mix) * s + wave_mix * sq) * env)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def crush(samples, bits=6, hold=3):
    """Bit-depth and sample-rate reduction: the scanline grit."""
    levels = 2 ** (bits - 1)
    out, last = [], 0.0
    for i, s in enumerate(samples):
        if i % hold == 0:
            last = round(s * levels) / levels
        out.append(last)
    return out


def normalize(samples):
    top = max(abs(s) for s in samples) or 1.0
    return [s / top * PEAK for s in samples]


def write_mp3(name, samples):
    samples = normalize(samples + silence(0.03))
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
        out = HERE / f"{name}.mp3"
        subprocess.run(
            ["lame", "--quiet", "-V", "4", "--noreplaygain", str(wav_path), str(out)],
            check=True,
        )
    print(f"wrote {out.relative_to(HERE.parent)}  ({len(samples) / RATE:.2f}s)")


def hop(freq=392.0, dur=0.055, up=19):
    """The frog's hop: a pure square swept up about an octave and a half."""
    return tone(freq, dur, wave_mix=1.0, attack=0.002, release=0.08, bend=up)


def noise(dur, hold=10, release=0.05):
    """Held random samples: a coarse, pitched-down buzz, like chip noise."""
    random.seed(7)  # keep the splat identical run to run
    n, out, last = int(RATE * dur), [], 0.0
    for i in range(n):
        if i % hold == 0:
            last = random.uniform(-1, 1)
        out.append(last * math.exp(-(i / RATE) / release))
    return out


def done():
    # Two hops, then home: a bright landing fifth (E5 -> B5) with the
    # #39ff14 glow as a quiet octave shimmer on top.
    out = hop(392.0) + silence(0.035) + hop(523.25) + silence(0.03)
    land = tone(659.25, 0.07, wave_mix=0.5, release=0.04) + tone(987.77, 0.22, wave_mix=0.5, release=0.09)
    glow = [0.0] * int(RATE * 0.07) + [s * 0.15 for s in tone(1975.5, 0.22, wave_mix=0.0, release=0.1)]
    return crush(out + mix(land, glow), bits=8, hold=2)


def request():
    # Look out: a hop cut short, a falling buzzy splat, then the site's
    # #0ff / #f0f glitch as two stuttered pulses a tritone apart.
    out = hop(392.0, dur=0.04) + silence(0.012)
    splat = mix(
        tone(880.0, 0.14, wave_mix=1.0, release=0.06, bend=-19),
        [s * 0.45 for s in noise(0.14)],
    )
    out += splat + silence(0.03)
    for f in (1318.5, 932.3):
        out += tone(f, 0.04, wave_mix=0.8, release=0.03) + silence(0.02)
    return crush(out, bits=5, hold=4)


if __name__ == "__main__":
    write_mp3("done", done())
    write_mp3("request", request())
