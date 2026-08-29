# AUDIO BIBLE — "Neon Afterhours" (authoritative sound direction)

The audio identity of Token Runner. Written before the round-4 audio build so
every parallel agent produces ONE coherent soundtrack instead of three
competing ones. Same contract-first pattern as VISUAL_BIBLE.md.

## Vision

It is 3AM. The apartment hums. The city outside is neon and indifferent.
**Late-night synthwave / lo-fi chiptune hybrid** — warm analog pads, mellow
detuned arps, soft dusty drums for exploration; menacing acid bass and driving
drums for combat. Comedy lives in the SFX (a deploy is a slot-machine win, a
death is a sad-trombone-shaped synth sting); the MUSIC plays it straight —
sincerity is what makes the jokes land.

Silence is a bug. The game must sound alive from the first menu frame.

## Hard rules (mixing law)

- Peak ceiling **-3 dBFS** on every generated file. Music RMS **-20..-14 dBFS**,
  ambience RMS **-30..-22 dBFS**, SFX peak **-6..-3 dBFS**. No DC offset
  (|mean| < 0.001). These are validated numerically after generation — they are
  not vibes.
- The AudioManager master limiter stays. The "no startle" principle stays:
  menu music fades in over ~1.5s, nothing ever cuts in at full level.
- Audio is **ON by default** (music_enabled true, modest default volumes).
  Silent-by-default was a placeholder-era safety, not a design decision.
- **Seamless loops**: music/ambience loop bar-exact. Total samples = an integer
  number of bars at the chosen BPM; every LFO, delay tail and arp wraps modulo
  the loop length. Loop seam |last sample - first sample| < 0.01.

## Track list (build-time generated, committed WAVs)

| File (assets/audio/) | Feel | BPM | Length |
|---|---|---|---|
| `music_menu.wav` | wistful nostalgic pad + slow arp, city-at-night | 80 | 32-48s |
| `music_explore.wav` | warm lo-fi groove, mellow lead, vinyl-ish hats | 84-92 | 45-64s |
| `music_combat.wav` | darksynth, acid 16th bass, driving kick | 124-132 | 30-48s |
| `music_boss.wav` | combat's angrier sibling, half-time drops | 124-140 | 30-48s |
| `music_victory.wav` | triumphant major-key fanfare -> groove | 100-120 | 15-30s |
| `ambient_interior.wav` | room tone: PSU hum, distant fridge | — | 20-30s |
| `ambient_industrial.wav` | rumble, metal resonance, steam | — | 20-30s |
| `ambient_outdoor.wav` | wind, night insects-as-synths | — | 20-30s |
| `ambient_ethereal.wav` | airy shimmer, slow spectral pad | — | 20-30s |

Music: **stereo** 44100 Hz 16-bit (width via detune/short delays, NOT phase
tricks that collapse in mono). Ambience: **mono**. Budget <= 8 MB per music
file. The legacy `menu_ambient.wav` / `ambient_localhost.wav` stay on disk
(other checkouts reference them) but the manager prefers the new set.

## SFX list (`sfx_<name>.wav`, mono, 0.05-1.2s; stings up to 3s)

Existing stream names KEEP THEIR NAMES (call sites depend on them):
`token_collect, quest_complete, upgrade, damage, coffee, ui_click, ui_hover,
ability, enemy_death`.

New: `footstep_0..3, dash, portal_enter, dialogue_blip, choice_select,
projectile_shoot, enemy_hit, player_death, heal, purchase, denied, achievement,
deploy_success, boss_spawn, pickup_rare, menu_open, menu_close, typing`.

Design language: every SFX is **layered** — transient (click/chirp) + body
(tonal, enveloped) + tail (filtered noise or short verb-ish decay). Nothing is
a naked sine. Comedy palette: `denied` = flat wrong-buzzer; `player_death` =
descending portamento "womp"; `deploy_success` = slot-machine arpeggio into a
major chord; `coffee` = percolator bubbles (band-passed noise blips).

## Runtime contract (audio_manager.gd owns this)

- Stream names above map to the generated files, **exists()-guarded** with the
  current synth beeps as fallback — the game must boot and sound OK at every
  intermediate state of the round.
- **Crossfade** between music tracks (two players, ~1.2s equal-power).
- **Ambience bus**: a third, quiet looping layer routed per region family:
  interior={localhost}, industrial={gpu_mines, dependency_district, production,
  token_vault}, outdoor={open_source_wildlands, stackoverflow_ruins,
  api_bazaar}, ethereal={cloud_district, corporate_enterprise}.
- SFX playback gets **pitch jitter ±6%** and a ~70ms per-name anti-machine-gun
  cooldown (footsteps exempt at ~140ms).
- Music **ducks -6 dB** while DialogueManager.is_active (tweened, 0.3s).
- All routing is **signal-driven from inside AudioManager** (region_changed,
  quest_completed, dialogue_started/ended, achievement_unlocked...). Do not
  add play_sfx call sites to files you do not own; report wants instead.

## Build-time generator contract

- `scripts/tools/music_generator.gd` and `scripts/tools/sfx_generator.gd`:
  `extends RefCounted`, expose `generate_all() -> void`, write WAVs via
  AudioStreamWAV.save_to_wav(). Invoked by run_generate.gd (already wired,
  exists()-guarded).
- run_generate.gd runs in **SceneTree script mode: autoloads DO NOT EXIST
  there** — generators must not touch GameManager/AudioManager/etc.
- GDScript performance: synthesize into PackedFloat32Array, precompute
  wavetables, no per-sample Dictionary lookups, no per-sample allocations.
  Whole-pipeline budget ~10 minutes.
- Determinism: seed all RNG (`seed()` / RandomNumberGenerator with fixed seed)
  so regeneration is reproducible.

## Numeric validation (run after generation; objective pass/fail)

For every WAV: duration within spec, peak <= -3 dBFS, RMS in band, |DC| <
0.001, loop-seam delta < 0.01, file parses as RIFF PCM16 at 44100 Hz.
