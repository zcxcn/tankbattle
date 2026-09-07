# Combat audio credits

Iron Embers uses locally packaged recordings and sound-library effects for its web version. These files are not fetched from outside services during play. The Android audio and PC audio files are unchanged.

## Attribution

Two sources are used under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/). The recordings have been trimmed, converted to mono, equalized, faded or looped, and normalized for this game; the authors do not endorse this project.

- **“Tank Engine Loop.flac” — qubodup**, [Freesound source](https://freesound.org/people/qubodup/sounds/200303/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used in `track-engine.wav`. We follow the current page's attribution license even though its description also mentions public domain.
- **“Light Machine Gun / lmg_fire01.mp3” — KuraiWolf / Nightshade Game Studios**, [OpenGameArt source](https://opengameart.org/content/light-machine-gun), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used in `mg-fire.wav`; trimmed and mastered for game playback.

The remaining sources are CC0 or explicitly public domain. Credits are retained for provenance:

| Source | Creator | License | Used for |
| --- | --- | --- | --- |
| [Tank Shots](https://freesound.org/people/qubodup/sounds/239135/) | qubodup | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | `cannon-01.wav`, `cannon-02.wav` |
| [Artillery Shots.flac](https://freesound.org/people/qubodup/sounds/182822/) | qubodup | CC0 1.0 | `cannon-03.wav` |
| [Explosion](https://freesound.org/people/qubodup/sounds/182429/) | qubodup | CC0 1.0 | Explosion, armor-impact and weapon-body layers |
| [Dropping sheet metal](https://freesound.org/people/SamsterBirdies/sounds/587442/) | SamsterBirdies | CC0 1.0 | Armor hits and explosive debris |
| [Sci-fi Sounds 1.0](https://kenney.nl/assets/sci-fi-sounds) | Kenney | CC0 1.0 | Blast layers, EMP, rail, cryo, grenade and scatter-shell sound design |
| [Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 | Armor knock, mechanical action and pickup confirmation |
| [Tank Tread](https://freesound.org/people/77Pacer/sounds/425271/) | 77Pacer | CC0 1.0 | `track-treads.wav` |
| [Missle Launch](https://soundbible.com/1794-Missle-Launch.html) | Kibblesbob | Public Domain, as stated on source page | `rocket-launch.wav` |
| [bullet ricochet.wav](https://freesound.org/people/aust_paul/sounds/30932/) | aust_paul | CC0 1.0 | `ricochet-01.wav`, `ricochet-02.wav` |

## Recording and design notes

The three main-gun reports are excerpts of actual tank/artillery recordings, identified by their source author as extracted from US government footage. Each file contains one report with the pressure wave and outdoor decay retained. Cannon 1 and 2 use two separate tank shots; cannon 3 uses a different artillery perspective. Mild filtering and rate adjustment suit the camera perspective without substituting rifle fire. The original recordings were obtained as the library's publicly served high-quality MP3 previews; converting these to PCM does not restore lossless-original detail.

Explosions and armor hits are edited composites. They combine an explosion recording with Kenney-designed low-frequency/crunch layers and real sheet-metal impacts. The armor impacts include a lower metal knock beneath the brighter debris. The sheet-metal source was recorded with a Tascam DR100mkIII. EMP, rail, cryo, grenade and scatter-shell effects are explicitly sound design, rather than claimed recordings of those fictional systems.

The tank engine is a field-recording excerpt. The tread layer is garage-door machinery recorded by its author for tank-tread foley; it is not a recording of military tracks. The rocket and ricochet clips are library effects; the ricochets are author-designed simulations. These distinctions follow the source descriptions.

The web bundle contains mono PCM16 WAV clips at 44.1 or 48 kHz. One-shots have short start fades, controlled tails, headroom and no embedded speech. Motion clips have wrap crossfades for continuous playback. `provenance.json` records each original URL and SHA-256, final file SHA-256, source slices, processing, duration, format and levels. The complete 19-clip pack occupies less than 4 MiB.

When redistributing, retain the two required CC BY attributions and their license links. A visible audio-credits link may point to this document.
