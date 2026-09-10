"""Verify decoded sound masters, provenance, radio bandwidth and loop seams."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT/'pc-godot/assets/audio/battlefield'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    provenance = json.loads((ASSETS/'provenance.json').read_text(encoding='utf-8'))
    assert len(provenance['files']) == 23, 'Expected 3 scores, 3 mechanical loops and 17 radio lines'
    checks = 1
    results = []
    for record in provenance['files']:
        path = ASSETS/record['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record['sha256'], f'Provenance mismatch: {path.name}'
        checks += 1
        with wave.open(str(path), 'rb') as w:
            assert w.getsampwidth() == 2
            rate = w.getframerate()
            samples = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float).reshape(-1, w.getnchannels())/32768
        peak, rms = float(abs(samples).max()), float(np.sqrt(np.mean(samples**2)))
        assert peak <= .94 and rms > .035 and abs(samples.mean(axis=0)).max() < .01, f'Clipping, silence or DC: {path.name}'
        checks += 1
        result = dict(file=record['file'], peak_dbfs=round(20*np.log10(peak), 3),
            rms_dbfs=round(20*np.log10(rms), 3), duration=round(len(samples)/rate, 3))
        if 'loop_seam_max' in record:
            seam = float(abs(samples[0]-samples[-1]).max())
            assert seam < .012, f'Loop discontinuity: {path.name} {seam}'
            checks += 1
            result['loop_seam'] = seam
        if record['file'].startswith('radio/'):
            f = np.fft.rfftfreq(len(samples), 1/rate)
            energy = abs(np.fft.rfft(samples[:,0]))**2
            ratio = float(energy[(f>=240)&(f<=4200)].sum()/energy.sum())
            assert ratio > .65, f'Radio-band speech is not dominant: {path.name}'
            checks += 1
            result['radio_band_energy_fraction'] = round(ratio, 4)
        if args.ffmpeg:
            decoded = subprocess.run([str(args.ffmpeg), '-v', 'error', '-i', str(path), '-f', 'null', '-'], capture_output=True, text=True)
            assert decoded.returncode == 0 and not decoded.stderr.strip(), f'Decode error: {path.name}: {decoded.stderr}'
            checks += 1
            result['ffmpeg_decode'] = 'PASS'
        results.append(result)
    report = dict(result='PASS', checks=checks, assets=len(results), bytes=provenance['total_bytes'], files=results)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
