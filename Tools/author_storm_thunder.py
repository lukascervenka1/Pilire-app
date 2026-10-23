#!/usr/bin/env python3
"""Author the quiet, distant storm rumble; no external recordings required.

Run on macOS: python3 Tools/author_storm_thunder.py
The slow attack avoids a thunderclap; SoundManager supplies the quiet mix level.
"""
import math
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import wave


def main():
    rate, duration = 44100, 6.8
    rng = random.Random(817)
    low = body = air = dc = 0.0
    samples = []
    for i in range(int(rate * duration)):
        t = i / rate
        noise = rng.uniform(-1, 1)
        low += 0.013 * (noise - low)
        body += 0.051 * (noise - body)
        air += 0.10 * (noise - air)
        dc += 0.0012 * (low - dc)
        attack = min(1, t / 0.75)
        attack = attack * attack * (3 - 2 * attack)
        tail = min(1, (duration - t) / 1.5)
        tail = tail * tail * (3 - 2 * tail)
        swell = 0.70 * math.exp(-t / 2.8) + 0.28 * math.exp(-((t - 2.6) / 0.85) ** 2)
        drift = 0.86 + 0.09 * math.sin(t * 5.4) + 0.05 * math.sin(t * 11.7)
        samples.append(((low - dc) * 4.0 + body * 0.7 + air * 0.15) * attack * tail * swell * drift)
    gain = 0.70 / max(abs(v) for v in samples)
    output = Path(__file__).resolve().parents[1] / 'Pilire/Sounds/amb_distant_thunder.m4a'
    with tempfile.TemporaryDirectory(prefix='pilire-thunder-') as folder:
        wav = Path(folder) / 'thunder.wav'
        with wave.open(str(wav), 'wb') as stream:
            stream.setparams((1, 2, rate, len(samples), 'NONE', 'not compressed'))
            stream.writeframes(b''.join(struct.pack('<h', round(v * gain * 32767)) for v in samples))
        subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac ', '-b', '96000', str(wav), str(output)], check=True)
    print(f'Authored {output.name}: {duration:.1f}s, {output.stat().st_size} bytes')


if __name__ == '__main__':
    main()
