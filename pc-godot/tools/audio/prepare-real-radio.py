"""Download verified Kenney actor recordings and prepare the offline PC radio.

Python + NumPy + FFmpeg. Never synthesizes speech, changes pitch, or splices
words into phrases. The pinned CC0 source ZIP includes named actor credits.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import urllib.request
import wave
import zipfile
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'pc-godot/assets/audio/battlefield'
SOURCE_URL = 'https://kenney.nl/assets/voiceover-pack'
EVIDENCE_URL = 'https://opengameart.org/content/voiceover-pack-40-lines'
DOWNLOAD_URL = 'https://kenney.nl/media/pages/assets/voiceover-pack/3f7f168698-1677589897/kenney_voiceover-pack.zip'
SOURCE_HASH = 'a5194df2f05f7ec439a8d4c1a7c20ba12ffe700d363a0733ae6fa826846af458'
RATE = 44100


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--source-zip', type=Path)
    args = parser.parse_args()
    cache = ROOT / 'work/audio-source/pc043'
    cache.mkdir(parents=True, exist_ok=True)
    archive = args.source_zip or cache / 'kenney_voiceover-pack.zip'
    if not archive.exists():
        request = urllib.request.Request(DOWNLOAD_URL, headers={'User-Agent': 'IronEmbersAssetPreparation/0.4.3'})
        with urllib.request.urlopen(request, timeout=60) as response, archive.open('wb') as target:
            shutil.copyfileobj(response, target)
    if digest(archive) != SOURCE_HASH:
        raise ValueError('Kenney ZIP does not match the reviewed CC0 archive')
    raw = cache / 'kenney'
    raw.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            target = (raw / member.filename).resolve()
            if not target.is_relative_to(raw.resolve()):
                raise ValueError('Unsafe archive member')
        package.extractall(raw)
    credits = OUT / 'radio/credits'
    credits.mkdir(parents=True, exist_ok=True)
    for original, output in [('License.txt', 'Kenney-Voiceover-License.txt'), ('Credits.txt', 'Kenney-Voiceover-Credits.txt')]:
        shutil.copyfile(raw / original, credits / output)
    lines = json.loads((Path(__file__).with_name('radio_lines.json')).read_text(encoding='utf-8'))
    records = []
    for event, line in lines.items():
        target = OUT / f'radio/{event}.wav'
        if line['source'] is None:
            # Delete only four explicitly identified obsolete PC TTS masters.
            if target.exists():
                target.unlink()
            if target.with_suffix('.wav.import').exists():
                target.with_suffix('.wav.import').unlink()
            continue
        source = raw / line['source']
        decoded = subprocess.run([str(args.ffmpeg), '-v', 'error', '-i', str(source), '-f', 'f32le', '-ac', '1', '-ar', str(RATE), '-'], capture_output=True, check=True)
        speech = np.frombuffer(decoded.stdout, dtype='<f4').astype(np.float64)
        # Wide, gentle radio coloration retains breath, consonants and the
        # actor's natural phrasing. No narrow 3.4 kHz telephone band, carrier
        # hiss, metallic distortion, formant/pitch shift or synthetic words.
        frequency = np.fft.rfftfreq(len(speech), 1 / RATE)
        response = 1 / np.sqrt(1 + (115 / np.maximum(frequency, 1)) ** 4)
        response *= 1 / np.sqrt(1 + (frequency / 6500) ** 8)
        speech = np.fft.irfft(np.fft.rfft(speech) * response, n=len(speech))
        speech -= speech.mean()
        active = np.abs(speech) > .008
        active_rms = float(np.sqrt(np.mean(speech[active] ** 2)))
        gain = min(.19 / max(active_rms, 1e-9), .88 / max(float(abs(speech).max()), 1e-9))
        speech *= gain
        fade = min(round(.005 * RATE), len(speech) // 2)
        speech[:fade] *= np.linspace(0, 1, fade)
        speech[-fade:] *= np.linspace(1, 0, fade)
        speech = np.pad(speech, (round(.035 * RATE), round(.07 * RATE)))
        pcm = np.rint(speech * 32767).astype('<i2')
        with wave.open(str(target), 'wb') as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(RATE)
            writer.writeframes(pcm.tobytes())
        records.append(dict(event=event, file=f'radio/{event}.wav', bytes=target.stat().st_size,
            sha256=digest(target), sample_rate=RATE, channels=1, duration_seconds=len(pcm)/RATE,
            peak=float(abs(pcm.astype(float)).max()/32768), rms=float(np.sqrt(np.mean((pcm.astype(float)/32768)**2))),
            clipped_samples=int(np.sum(np.abs(pcm.astype(float)) >= 32767)), source='kenney-voiceover-pack',
            source_file=line['source'], source_sha256=digest(source), performer=line['performer'],
            transcript=line['transcript'], caption=line['caption'], human_recording=True, language='en',
            processing='Original complete actor take; mono 44.1kHz PCM16; gentle 115Hz high-pass / 6.5kHz low-pass; transparent gain normalization and 5ms endpoint fades. No pitch or timing changes.'))
    provenance = json.loads((OUT / 'provenance.json').read_text(encoding='utf-8'))
    provenance['version'] = 2
    provenance['files'] = [record for record in provenance['files'] if not record['file'].startswith('radio/')] + records
    provenance['sources'] = [s for s in provenance['sources'] if s['id'] != 'kenney-voiceover-pack'] + [dict(
        id='kenney-voiceover-pack', title='Voiceover Pack #1', creator='Kenney', license='CC0-1.0',
        licenseUrl='https://creativecommons.org/publicdomain/zero/1.0/', sourceUrl=SOURCE_URL,
        performerEvidenceUrl=EVIDENCE_URL, downloadUrl=DOWNLOAD_URL, sourceSha256=SOURCE_HASH,
        performers=['Jeffrey M. Smith (male)', 'Giselle (female)'],
        licenseFile='radio/credits/Kenney-Voiceover-License.txt', creditsFile='radio/credits/Kenney-Voiceover-Credits.txt')]
    provenance['speech'] = '13 complete English actor recordings from Kenney Voiceover Pack (Jeffrey M. Smith and Giselle), with accurate Chinese subtitles. No synthesized speech.'
    provenance['notice_only_events'] = {event: line['caption'] for event, line in lines.items() if line.get('notice_only')}
    provenance['total_bytes'] = sum(record['bytes'] for record in provenance['files'])
    (OUT / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'actor_clips': len(records), 'notice_only_events': list(provenance['notice_only_events']), 'source_sha256': SOURCE_HASH}, indent=2))


if __name__ == '__main__':
    main()
