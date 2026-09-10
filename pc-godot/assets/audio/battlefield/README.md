# Battlefield music, Chinese radio and vehicle mechanics

All clips are packaged for offline PC playback. No Red Alert audio, character
voice, commercial-game sample, performer imitation or runtime audio service is
used. The game's tactical-radio style uses original lines, receiver tones and
radio processing.

## Music

`music/industrial-war.wav` (钢铁风暴, industrial combat, 136 BPM),
`music/electronic-pursuit.wav` (极速追击, electronic pursuit, 160 BPM), and
`music/epic-siege.wav` (决战重围, orchestral-style drums/brass, 144 BPM) are
original procedural compositions from `scripts/generate-combat-music.py`.
They reuse this project's existing original stereo masters without modification.
No external samples or existing melodies are used. Circular event tails,
reverbs and filters preserve uninterrupted forward loops. These are original
synthesized scores, not recordings of a live orchestra.

## Chinese command radio

Seventeen Chinese lines are authored in `pc-godot/tools/audio/radio_lines.json`.
They were synthesized locally with the Windows **Microsoft Huihui Desktop —
Chinese (Simplified)** voice, rate +1, mono 22.05 kHz PCM16, on 2026-09-10.
The installed voice itself is not redistributed. This is computer-synthesized
speech, not a voice actor recording or an imitation of any named individual.
`scripts/process-radio.py` applies a 270–3400 Hz bandpass, soft compression,
quiet radio carrier, receiver chirp and closing squelch. Gameplay serializes
reports, limits repeated announcements and lowers music under spoken reports.

Regenerate on Windows with the Huihui desktop voice installed:

```powershell
./pc-godot/tools/audio/generate-radio.ps1 -Python python
python pc-godot/tools/audio/prepare-battlefield.py
```

The second command needs NumPy and only writes this PC audio directory. The
existing web and frozen Android resources remain separate.

## Required engine attribution

**“Tank Engine Loop.flac” — qubodup**, [Freesound source](https://freesound.org/people/qubodup/sounds/200303/),
licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
Used in `vehicle/track-engine.wav`. Retain this attribution when redistributing.
The author does not endorse the game. We retain the attribution license recorded
for the source page, whose description additionally mentioned public domain.

The processed field-recording excerpt was copied from the project's previously
licensed combat pack and given a smooth 3 ms loop-boundary correction. Prior
processing comprised mono conversion, 42–1500 Hz bandpass, excerpt selection,
wrap crossfade and gain normalization. This is an actual tank-engine recording.

## Tread and steering attribution

**“Tank Tread” — 77Pacer**, [Freesound source](https://freesound.org/people/77Pacer/sounds/425271/),
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
Used in `vehicle/track-treads.wav` and derived `vehicle/track-turn.wav`.
The author recorded sliding-garage-door machinery for tank-tread foley; these
are mechanical sound-design layers, not claimed recordings of military tracks.
The processed loop was copied from the project's licensed pack, with a smooth
3 ms loop-boundary correction. The turn variant adds a circular midrange
friction filter and original steel-resonance synthesis. Collision playback
reuses the already credited armor-impact variants from `../combat/README.md`.

`provenance.json` retains source URLs and hashes, output SHA-256 hashes,
processing details, formats, duration, levels and loop seam measurements.
