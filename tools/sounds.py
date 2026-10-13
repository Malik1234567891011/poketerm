"""Original 8-bit jingles for poketerm (pulse + triangle channels, like a Game Boy).

  sounds/levelup.wav  Claude finished a turn
  sounds/alert.wav    Claude needs you (the "!" a trainer gets when spotted)
  sounds/bell.wav     terminal bell in Ghostty
"""
import math
import pathlib
import struct
import wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sounds"


def note(n):
    """Note name like 'G5' -> frequency."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    return 440.0 * 2 ** ((names[n[:-1]] + 12 * (int(n[-1]) - 4)) / 12)


def pulse(f, t, duty=0.25):
    return 1.0 if (f * t) % 1.0 < duty else -1.0


def tri(f, t):
    x = (f * t) % 1.0
    return 4 * abs(x - 0.5) - 1


def render(voices, length):
    """voices: list of (kind, [(start, dur, note, vol)]) -> samples."""
    buf = [0.0] * int(RATE * length)
    for kind, events in voices:
        for start, dur, n, vol in events:
            f = note(n)
            s0 = int(start * RATE)
            for i in range(int(dur * RATE)):
                t = i / RATE
                env = min(1.0, t / 0.004) * math.exp(-t * (2.5 / dur))
                vib = 1 + 0.004 * math.sin(2 * math.pi * 6 * t) * min(1, t / 0.08)
                v = pulse(f * vib, t, 0.25 if kind == "p1" else 0.125) if kind != "tri" else tri(f, t)
                if s0 + i < len(buf):
                    buf[s0 + i] += v * vol * env
    peak = max(abs(x) for x in buf) or 1
    return [x / peak * 0.8 for x in buf]


def save(name, samples):
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / name), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))


def main():
    # level up: bright pulse arpeggio over a triangle bass, then a held top note
    s = 0.075
    lead = [(0, s, "G5", .5), (s, s, "B5", .5), (2 * s, s, "D6", .5), (3 * s, s, "G6", .5),
            (4 * s, s * 0.8, "F#6", .45), (4.9 * s, s * 0.8, "G6", .45), (6 * s, 0.42, "B6", .55)]
    harm = [(0, s * 2, "D5", .3), (2 * s, s * 2, "G5", .3), (6 * s, 0.42, "D6", .3)]
    bass = [(0, s * 3, "G3", .6), (3 * s, s * 3, "D4", .6), (6 * s, 0.42, "G4", .6)]
    save("levelup.wav", render([("p1", lead), ("p2", harm), ("tri", bass)], 1.0))

    # alert: two quick blips and a rising "!"
    lead = [(0, 0.06, "E6", .5), (0.09, 0.06, "E6", .5), (0.18, 0.2, "B6", .55)]
    bass = [(0, 0.06, "E4", .5), (0.09, 0.06, "E4", .5), (0.18, 0.2, "B4", .5)]
    save("alert.wav", render([("p1", lead), ("tri", bass)], 0.45))

    # bell: one soft pulse ping
    save("bell.wav", render([("p2", [(0, 0.18, "A6", .4)]), ("tri", [(0, 0.18, "A5", .4)])], 0.25))


if __name__ == "__main__":
    main()
