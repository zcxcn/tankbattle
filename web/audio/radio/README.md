These 21 English command lines are written for Iron Embers. Speech was synthesized locally with the Windows English (US) Microsoft Zira desktop voice, then given an original narrow-band radio treatment, receiver chirp, compression, and squelch. No Red Alert recordings, performer samples, or external audio services are used.

The script lives in `lib/tactical-radio.ts`. On Windows with the Zira desktop voice, Node, and Python installed, regenerate with `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/generate-radio.ps1`. `scripts/process-radio.py` applies the deterministic radio processing.

WAV files are mono 22.05 kHz PCM16. Vite imports them through `lib/radio-assets.ts` so the web build gets correctly based, hashed URLs while the frozen Android build includes none of these clips. Engine and track audio are generated in `lib/track-audio.ts` without external samples.
