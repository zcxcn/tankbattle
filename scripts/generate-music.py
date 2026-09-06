#!/usr/bin/env python3
"""Original, deterministic D-minor game score. Requires Python 3 and NumPy.

Three additive, synchronized 100 BPM / 4/4 / 8-bar stems. All event tails,
delay taps and filtering wrap on the 19.2 second musical cycle. No samples
or existing compositions are used. Run: python3 generate_music.py
"""
from pathlib import Path
import json
import math
import wave
import numpy as np

SR = 22050
BPM = 100
BEAT = 60.0 / BPM
BARS = 8
DURATION = BARS * 4 * BEAT
N = round(DURATION * SR)
OUT = Path(__file__).resolve().parent.parent / 'public' / 'music'
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(860609)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def timeline(seconds):
    return np.arange(round(seconds * SR), dtype=np.float64) / SR


def envelope(t, gate, attack=0.02, release=0.25, decay=0.0):
    """Smooth starts and full, zero-ended releases prevent event clicks."""
    a = np.sin(0.5 * np.pi * np.minimum(t / attack, 1.0)) ** 2
    r = np.cos(0.5 * np.pi * np.clip((t - gate) / release, 0, 1)) ** 2
    return a * r * np.exp(-decay * t)


def put(track, beat, signal, gain=1.0):
    start = round(beat * BEAT * SR)
    indexes = (start + np.arange(len(signal))) % N
    track[indexes] += signal * gain


def spectral_filter(x, cutoff=3500.0, highpass=0.0, order=3):
    """Zero-phase circular filter also preserves the musical loop boundary."""
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    response = 1.0 / np.sqrt(1.0 + (f / cutoff) ** (2 * order))
    if highpass:
        response *= 1.0 - np.exp(-(f / highpass) ** 4)
    response[0] = 0.0
    return np.fft.irfft(np.fft.rfft(x) * response, n=len(x))


def noise(t, center, width):
    f = np.fft.rfftfreq(len(t), 1.0 / SR)
    shape = np.exp(-0.5 * ((f - center) / width) ** 2)
    n = np.fft.irfft(np.fft.rfft(RNG.normal(size=len(t))) * shape, n=len(t))
    return n / max(np.std(n), 1e-12)


def strings(midi, gate, level=1.0):
    release = 0.82
    t = timeline(gate + release)
    f = hz(midi)
    signal = np.zeros(len(t))
    # Three subtly detuned, rounded bowed voices; upper partials roll off.
    for cents, weight in [(-5.2, 0.23), (0.0, 0.54), (5.5, 0.23)]:
        phase = 2 * np.pi * f * 2 ** (cents / 1200) * t
        phase += 0.017 * np.sin(2 * np.pi * 4.2 * t + midi * 0.17)
        for partial, amplitude in [(1, .72), (2, .25), (3, .14),
                                   (4, .065), (5, .025), (7, .009)]:
            signal += weight * amplitude * np.sin(partial * phase + partial * .31)
    bow = noise(t, 1350.0, 530.0) * .007
    slow_swell = .89 + .11 * np.sin(2 * np.pi * .29 * t - .8)
    return (signal + bow) * envelope(t, gate, .20, release) * slow_swell * level


def lead(midi, beats, velocity=1.0):
    gate = beats * BEAT
    release = .34
    t = timeline(gate + release)
    phase = 2 * np.pi * hz(midi) * t
    phase += .035 * np.sin(2 * np.pi * 4.7 * t) * np.minimum(t / .3, 1)
    # A muted reed/cello hybrid with a short wooden attack, not a pure tone.
    body = (.78 * np.sin(phase + .12 * np.sin(2 * phase) * np.exp(-2*t))
            + .20 * np.sin(2*phase + .3) + .12*np.sin(3*phase + .5)
            + .032*np.sin(5*phase))
    body *= (.83 + .17*np.exp(-5*t))
    air = noise(t, 1250, 500) * .009 * np.exp(-2*t)
    return (body + air) * envelope(t, gate, .025, release, .12) * velocity


def pluck(midi, beats=.4, bright=.8):
    gate = beats * BEAT
    release = .22
    t = timeline(gate + release)
    p = 2 * np.pi * hz(midi) * t
    body = np.sin(p + bright * np.exp(-12*t) * np.sin(2*p))
    body += .12 * np.sin(2*p + .2) * np.exp(-5*t)
    return body * envelope(t, gate, .006, release, 4.8)


def bass(midi, beats=.75, accent=1.0):
    gate = beats * BEAT
    release = .13
    t = timeline(gate + release)
    p = 2 * np.pi * hz(midi) * t
    body = np.sin(p + .15*np.exp(-8*t)*np.sin(p))
    body += .18*np.sin(2*p) + .055*np.sin(3*p)
    return body * envelope(t, gate, .012, release, .35) * accent


def kick(strength=1.0):
    t = timeline(.56)
    # Integrated pitch sweep lands on a deep, controlled drum fundamental.
    phase = 2*np.pi*(47*t + 70*.025*(1-np.exp(-t/.025)))
    body = np.sin(phase) * np.exp(-t/ .13)
    thump = .12 * noise(t, 310, 190) * np.exp(-t/.024)
    return (body+thump) * envelope(t, .38, .003, .18) * strength


def war_drum(midi=42, strength=1.0):
    t = timeline(.9)
    f = hz(midi)
    phase = 2*np.pi*(f*t + f*.19*.04*(1-np.exp(-t/.04)))
    body = (np.sin(phase) + .27*np.sin(1.48*phase+.3)
            + .13*np.sin(2.12*phase+.1)) * np.exp(-t/.23)
    skin = .19 * noise(t, 630, 430) * np.exp(-t/.065)
    return (body+skin)*envelope(t, .62, .003, .28)*strength


def snare(strength=1.0):
    t = timeline(.42)
    skin = .62 * noise(t, 1500, 820)*np.exp(-t/.058)
    wood = .33*np.sin(2*np.pi*169*t)*np.exp(-t/.065)
    return (skin+wood)*envelope(t, .20, .0025, .22)*strength


def shaker(strength=1.0):
    t = timeline(.13)
    n = noise(t, 3000, 700)
    return n*np.exp(-t/.024)*envelope(t,.065,.004,.065)*strength


def hall(x, wet=.24):
    # Dense, dark, circular room reflections: all delayed tails cross bar 8.
    source = spectral_filter(x, 2000, 110, order=2)
    reflections = np.zeros(N)
    for sec, weight in [(.041,.40),(.073,.34),(.113,.30),(.149,.25),
                        (.211,.22),(.283,.19),(.337,.16),(.419,.13),
                        (.521,.105),(.643,.087),(.787,.066),(.947,.05),
                        (1.127,.038),(1.363,.028),(1.681,.018)]:
        reflections += weight*np.roll(source,round(sec*SR))
    return x + wet*reflections


def finish(x, cutoff, drive=1.1):
    x = spectral_filter(x, cutoff, 25, order=3)
    x = np.tanh(x*drive)
    x -= np.mean(x)
    # Peak normalize each finished stem to the requested headroom.
    x *= .65 / max(np.max(np.abs(x)), 1e-12)
    return x


def main():
    atmosphere = np.zeros(N)
    combat = np.zeros(N)
    boss = np.zeros(N)
    # Dm, Bb, F, C, Dm, Bb, Gm, A: intentional dominant return to Dm.
    chords = [[50,57,62,65], [46,53,58,62], [48,53,57,60], [48,55,60,64],
              [50,57,62,65], [46,53,58,62], [43,50,58,62], [45,52,57,61]]
    roots = [38,34,41,36,38,34,31,33]
    chord_labels = ['Dm','Bb','F','C','Dm','Bb','Gm','A']
    # Original two-part motif: rise by a third, answer downward, then vary.
    melody = [
        [(0,62,.85),(1,65,.45),(1.5,69,1.25),(3,65,.70)],
        [(0,62,1.25),(1.5,65,.65),(2.5,62,.55),(3.25,60,.50)],
        [(0,60,.85),(1,57,.55),(2,60,.60),(3,64,.70)],
        [(0,67,1.15),(1.5,64,.65),(2.5,62,.80)],
        [(0,62,.85),(1,65,.45),(1.5,69,.65),(2.5,72,.55),(3.25,69,.50)],
        [(0,70,1.20),(1.5,69,.60),(2.5,65,.60),(3.25,62,.50)],
        [(0,67,.85),(1,65,.55),(2,62,.70),(3,58,.65)],
        [(0,61,.85),(1,64,.65),(2,69,.65),(3,61,.65)],
    ]
    for bar, chord in enumerate(chords):
        origin = bar*4
        for voice, note in enumerate(chord):
            put(atmosphere, origin, strings(note,4*BEAT+.02),
                [.082,.061,.062,.048][voice])
        # Restrained low root reinforces the score when heard alone.
        put(atmosphere, origin, strings(roots[bar],3.7*BEAT), .028)
        for step, note, length in melody[bar]:
            vel = .90 if step in (0, 1.5) else .77
            put(atmosphere,origin+step,lead(note,length,vel),.155)
        for step,note in [(0.5,chord[1]+12),(2.5,chord[2]+12)]:
            put(atmosphere,origin+step,pluck(note,.6,.45),.023)

        root=roots[bar]
        # Complementary, syncopated bass and broad military drums.
        for step,note,length,strength in [(0,root,.85,1),(1,root,.42,.7),
                (1.75,root+12,.2,.45),(2,root,.75,.9),(3,root+7,.4,.65),
                (3.5,root,.35,.60)]:
            put(combat,origin+step,bass(note,length,strength),.34)
        for step,gain in [(0,.39),(1.5,.22),(2,.34),(3.5,.20)]:
            put(combat,origin+step,kick(),gain)
        for step,gain in [(1,.19),(3,.22)]:
            put(combat,origin+step,snare(),gain)
        for step,note,gain in [(0,38,.15),(2.75,43,.105),(3.5,41,.085)]:
            put(combat,origin+step,war_drum(note),gain)
        for step in np.arange(.5,4,.5):
            put(combat,origin+step,shaker(),.022 if step%1 else .013)

        # Boss layer: middle-register wooden ostinato and answering toms.
        order=[0,1,2,1,3,2,1,2]
        for index,voice in enumerate(order):
            note=chord[voice]+12
            put(boss,origin+index*.5,pluck(note,.36,.9),
                .132 if index in (0,4) else .092)
        for step,note,gain in [(0,38,.18),(.75,45,.09),(1.5,43,.15),
                              (2.5,46,.105),(3,43,.12),(3.5,41,.14)]:
            put(boss,origin+step,war_drum(note),gain)
        if bar in (3,7):
            for step,note,gain in [(3.25,48,.075),(3.75,43,.105)]:
                put(boss,origin+step,war_drum(note),gain)
        # Breath-like sweep is deliberately quiet and avoids cymbal glare.
        t=timeline(4*BEAT)
        swell=noise(t,1050,550)*np.sin(np.pi*t/(4*BEAT))**4
        put(boss,origin,swell,.006)

    atmosphere=finish(hall(atmosphere,.31),3400,1.18)
    combat=finish(hall(combat,.085),4300,1.12)
    boss=finish(hall(boss,.18),3300,1.14)

    report={'title':'Iron Embers — Ashes at Dawn',
            'composition':'Original procedural synthesis; no sampled music',
            'sample_rate':SR,'channels':1,'sample_width_bits':16,
            'bpm':BPM,'time_signature':'4/4','bars':BARS,
            'duration_seconds':DURATION,'frames_per_stem':N,
            'chords':chord_labels,'stems':{},
            'suggested_simultaneous_gains':
                {'atmosphere':.55,'combat':.45,'boss':.30}}
    for name,x in [('atmosphere',atmosphere),('combat',combat),('boss',boss)]:
        pcm=np.rint(x*32767).astype('<i2')
        with wave.open(str(OUT/(name+'.wav')),'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes(pcm.tobytes())
        decoded=pcm.astype(np.float64)/32768
        delta=float(decoded[0]-decoded[-1])
        d=np.diff(decoded)
        report['stems'][name]={
            'path':str(OUT/(name+'.wav')),
            'bytes':(OUT/(name+'.wav')).stat().st_size,
            'peak':float(np.max(np.abs(decoded))),
            'rms':float(np.sqrt(np.mean(decoded**2))),
            'dc':float(np.mean(decoded)),
            'first_last_difference':delta,
            'first_last_abs_difference':abs(delta),
            'adjacent_difference_rms':float(np.sqrt(np.mean(d*d))),
            'adjacent_difference_peak':float(np.max(np.abs(d))),
            'clipped_samples':int(np.sum(np.abs(pcm.astype(np.int32))>=32767)),
        }
    mix=atmosphere*.55+combat*.45+boss*.30
    report['suggested_mix_peak']=float(np.max(np.abs(mix)))
    report['suggested_mix_rms']=float(np.sqrt(np.mean(mix**2)))
    report_dir = Path(__file__).resolve().parent.parent / 'outputs' / 'music'
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir/'analysis.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
