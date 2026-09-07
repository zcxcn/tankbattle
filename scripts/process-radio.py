"""Apply an original narrow-band field-radio treatment to locally generated speech."""
import array
import math
from pathlib import Path
import random
import sys
import wave


def process(source, destination):
    with wave.open(str(source), 'rb') as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
        rate = wav.getframerate()
        samples = array.array('h', wav.readframes(wav.getnframes()))
    if sys.byteorder != 'little':
        samples.byteswap()
    # Trim excess synthesizer silence, retaining consonant attacks and tails.
    audible = [i for i, value in enumerate(samples) if abs(value) > 100]
    assert audible, f'Empty speech: {source}'
    samples = samples[max(0, audible[0] - int(rate * .025)):audible[-1] + int(rate * .08)]
    hp = math.exp(-2 * math.pi * 270 / rate)
    lp = 1 - math.exp(-2 * math.pi * 3400 / rate)
    prior = high = low = 0.0
    speech = []
    for value in samples:
        value /= 32768
        high = hp * (high + value - prior)
        prior = value
        low += lp * (high - low)
        speech.append(low)
    scale = .8 / max(abs(value) for value in speech)
    rng = random.Random(source.stem)
    result = []
    # Short receiver chirp, squelch, then speech with a quiet carrier texture.
    for i in range(int(rate * .14)):
        t = i / rate
        chirp = .085 * math.sin(2 * math.pi * (1080 if t < .04 else 810) * t) if t < .075 else 0
        noise = (rng.random() * 2 - 1) * .045 if .08 < t < .125 else 0
        result.append((chirp + noise) * min(1, t / .006))
    for i, value in enumerate(speech):
        envelope = min(1, i / (rate * .008), (len(speech) - 1 - i) / (rate * .012))
        result.append((.83 * math.tanh(value * scale * 2) + (rng.random() * 2 - 1) * .0025) * envelope)
    for i in range(int(rate * .09)):
        result.append((rng.random() * 2 - 1) * .035 * math.exp(-i / (rate * .015)))
    result[-1] = 0
    pcm = array.array('h', (round(max(-.9, min(.9, value)) * 32767) for value in result))
    if sys.byteorder != 'little':
        pcm.byteswap()
    with wave.open(str(destination), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(pcm.tobytes())
    print(f'{destination.name}: {len(result) / rate:.2f}s')


if __name__ == '__main__':
    source_dir, output_dir = map(Path, sys.argv[1:])
    output_dir.mkdir(parents=True, exist_ok=True)
    for source in sorted(source_dir.glob('*.wav')):
        process(source, output_dir / source.name)
