# Attribution

## External Assets (CC0)

### Kenney — Tiny Town
- **Source:** [Kenney Tiny Town](https://kenney.nl/assets/tiny-town) via [OpenGameArt](https://opengameart.org/content/tiny-town)
- **License:** [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
- **Used for:** Localhost apartment floor tiles, walls, furniture props, environmental decoration
- **Location:** `assets/external/kenney/tiny-town/`

### Kenney — Roguelike Characters
- **Source:** [Kenney Roguelike Characters](https://kenney.nl/assets/roguelike-characters) via [OpenGameArt](https://opengameart.org/content/roguelike-character-pack)
- **License:** [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
- **Used for:** Archived reference only — player now uses procedural vibe-coder sprite (see below)
- **Location:** `assets/external/kenney/roguelike/roguelikeChar_transparent.png`

### Kenney — Game Assets All-in-1 (3D kits)
- **Source:** [Kenney](https://kenney.nl/assets) — Mini Characters, Mini Dungeon, Mini Arena, Mini Market, Mini Forest, Graveyard Kit, Cube Pets, Tower Defense Kit, Space Station Kit, Modular Space Kit, Modular Cave Kit, Factory Kit, City Kit (Commercial, Industrial), Retro Urban Kit, Castle Kit, Prototype Kit, Food Kit, Furniture Kit, Nature Kit
- **License:** [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) (per-pack License.txt vendored alongside)
- **Used for:** the 3D world — characters, enemies, regions, props (see docs/3D_BIBLE.md)
- **Location:** `assets/external/kenney3d/<pack>/` (GLB + colormap), index in `manifest.json`

Attribution to Kenney.nl is appreciated but not required under CC0.

## Procedurally Generated (Internal)

- **Player character:** 64×64 spritesheet — hoodie vibe-coder, 4-dir walk, comedic idles — `scripts/tools/asset_generator_runtime.gd`
- **Ambient music:** Soft pad loops composed via ffmpeg with limiter — `assets/audio/menu_ambient.wav`, `assets/audio/ambient_localhost.wav` (original, safe levels)
- Placeholder SFX (gated, conservative volumes): `scripts/autoload/audio_manager.gd`

## Third-Party Software

- [Godot Engine](https://godotengine.org/) — MIT License
