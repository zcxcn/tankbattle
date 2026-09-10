# Battlefield music, actor radio and vehicle mechanics

All clips are packaged for offline PC playback. Radio performances are licensed
actor recordings. No Red Alert audio, commercial-game sample, voice cloning,
TTS speech or runtime audio service is used.

## Music

`music/industrial-war.wav` (钢铁风暴, industrial combat, 136 BPM),
`music/electronic-pursuit.wav` (极速追击, electronic pursuit, 160 BPM), and
`music/epic-siege.wav` (决战重围, orchestral-style drums/brass, 144 BPM) are
original procedural compositions from `scripts/generate-combat-music.py`.
They reuse this project's existing original stereo masters without modification.
No external samples or existing melodies are used. Circular event tails,
reverbs and filters preserve uninterrupted forward loops. These are original
synthesized scores, not recordings of a live orchestra.

## English actor recordings and Chinese subtitles

**Voiceover Pack #1 — Kenney**, [official source](https://kenney.nl/assets/voiceover-pack),
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The source archive identifies **Jeffrey M. Smith** as the male performer and
**Giselle** as the female performer. Kenney's
[original 2015 publication](https://opengameart.org/content/voiceover-pack-40-lines)
also describes recordings by male and female voice actors. Original archive
documents are retained without modification in
`radio/credits/Kenney-Voiceover-License.txt` and
`radio/credits/Kenney-Voiceover-Credits.txt`.

Thirteen complete recorded takes cover combat and mission reactions. Chinese
subtitles translate the actual English words, not an unrelated event script.
For example, “Target destroyed!” is “目标已摧毁！”, and “Look out!” is “小心！”.
Low ammunition, ammunition depleted, armor restored and mines cleared have no
matching take in this pack: those four events use accurate Chinese status text
and a quiet interface cue. They do not play substituted or synthesized words.

Audio preparation retains the original pitch, phrasing and performance. It
uses mono 44.1 kHz PCM16, gentle 115 Hz high-pass / 6.5 kHz low-pass filtering,
transparent gain normalization, 5 ms endpoint fades and short silent padding.
There is no word splicing, voice imitation, hard compression or carrier hiss.
Gameplay keeps the bounded priority queue, cooldowns, pause handling and music
ducking during spoken reports. Short shouts keep their subtitles visible for
at least 1.8 seconds; text notices do not duck the music.

To reproduce, with Python, NumPy and FFmpeg installed:

```powershell
python pc-godot/tools/audio/prepare-real-radio.py --ffmpeg path/to/ffmpeg.exe
python pc-godot/tools/audio/verify-battlefield.py --ffmpeg path/to/ffmpeg.exe
```

The preparation script downloads only the original CC0 archive, verifies its
pinned SHA-256, and records source-take/output hashes and English/Chinese text
in `provenance.json`. `prepare-battlefield.py` can still regenerate music and
mechanics while preserving these actor records. Old PC TTS generation was
removed. The existing web and frozen Android resources remain separate.

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
