# Autonomous Development Status

**Last Updated:** 2026-08-28  
**Current Objective:** v1.0 PO review failed — rebuilding Localhost to Steam-page quality

## Honest Assessment

**Would I put this on a Steam page today?** Closer — maybe as an *Early Access / wishlist* teaser with caveats — but not as a polished launch gallery. Localhost now reads as an intentional vibe-coding scene rather than a gray prototype, and the Dream App panel matches the HUD theme. The procedural hoodie player is recognizable and on-theme, though still clearly programmer art.

### What was broken in v1.0 (PO feedback)
- Gray viewport borders, tiled rectangle world, tiny sprites
- Debug-style HUD with raw labels
- **P0: Loud/static startup audio** from procedural ambient loops auto-playing on menu + world load

### What was rebuilt (this session + prior)
- **P0 Audio:** Startup music disabled by default. Separate Music/SFX buses. Conservative volumes. `music_enabled` gate — silent until settings opt-in.
- **Localhost only:** Hand-crafted `LocalhostBuilder` — 3AM coder apartment with desk/monitors, server rack, pizza boxes, GPU boxes, sticky notes, environmental jokes, point lights.
- **External assets:** Kenney Tiny Town (environment) — documented in ATTRIBUTION.md.
- **Player character:** Procedural vibe-coder hoodie sprite (laptop glow, headphones, walk/idle/hurt/celebrate) — replaces Kenney fantasy roguelike.
- **Camera:** Closer framing (zoom 1.35), smoothing enabled, player scale 2.8× on 32×48 sprite.
- **HUD:** Full redesign — top bar with typed labels, quest panel, hint bar. Custom `GameTheme`.
- **Dream App UI:** Holographic dev-console styling — backdrop dim, cyan accent, pulsing panel, themed buttons. Matches HUD.
- **Main menu:** Dark tech-noir panel layout, no auto music.
- **Opening sequence:** Boot terminal → token warnings → press key → Claude dialogue auto-starts.
- **Tokens:** Glow lights, stronger magnet, bob animation, collection VFX.
- **Repo hygiene:** Removed duplicate untracked `assets/external/roguelike-characters/` and `assets/external/tiny-town/` (canonical paths under `assets/external/kenney/`).

### What still needs work before v2.0
- Player sprite is procedural pixel art — readable silhouette but not Steam-trailer quality; would benefit from a proper 32×48 or 64×64 sprite sheet
- Isometric Kenney tiles in top-down layout — readable but not true 2.5D
- Other 9 regions untouched (intentionally deprioritized)
- Music still procedural placeholder — needs real CC0 ambient track when validated
- Screenshot capture requires headed Godot (Metal/OpenGL); headless dummy renderer cannot grab frames

## Playtest Notes (2026-08-28)
- Boot: **Silent** on main menu ✓
- New game: Opening terminal sequence plays, player frozen until keypress ✓
- Localhost: Warm ambient, monitor glow, props visible, Claude at desk ✓
- Player: Hoodie coder silhouette visible at camera zoom, walk cycle animates ✓
- Dream App (Tab): Holographic panel with themed upgrade tree ✓
- Smoke tests: 8/8 passing ✓

## Testing State
- 8/8 smoke tests passing
- Project boots at 1920×1080 without gray letterboxing
- Screenshots re-captured at 1920×1080 (via `capture_main.gd`)

## Release Readiness
- **NOT ready for v2.0** — Localhost quality gate improving but not fully passed
- **P0 audio hazard: FIXED** — silent startup confirmed
- **Steam page gallery:** Usable for internal review / wishlist draft; would hold back hero shot until custom character art lands
- v1.0 tag remains; work continues on main toward quality transformation

## Capture method
Headless rendering cannot grab viewport textures (dummy renderer). Use:
```bash
godot --path . --resolution 1920x1080 --script res://tools/capture_main.gd
```
Output is normalized to 1920×1080 PNG in `docs/screenshots/`:
- `01_localhost_establishing.png` — apartment overview
- `02_npc_interaction.png` — Claude dialogue
- `03_token_collection.png` — token pickup with glow
- `04_dream_app_ui.png` — Dream App holographic panel

## Next Tasks
- Commission or source proper CC0 vibe-coder sprite sheet (hoodie, laptop, 4-dir walk)
- Real CC0 ambient music (after validation pass)
- Do not expand beyond Localhost until Steam-page test passes
