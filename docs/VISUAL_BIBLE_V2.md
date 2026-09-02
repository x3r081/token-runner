# VISUAL BIBLE v2 — RESTRAINT

**Supersedes any conflicting rule in VISUAL_BIBLE.md.** v1 taught the project to
add; v2 teaches it to stop. The brief that triggered this: *"too much AI slop —
I expect much cleaner and MUCH better graphics."*

## What "AI slop" means here, concretely

Slop is the look of a scene where nothing was ever removed. Its signatures in
our current frames, all confirmed by looking, not guessing:

| Signal | Evidence in our frames |
|---|---|
| Mixed pixel density | 32px tiles at 2.0x, NPCs at 2.2x, tokens at 2.5x, vector-smooth text, anti-aliased rounded plates — five different pixel sizes in one frame |
| No quiet | 25 tokens/region, 55 world labels with plates + accent bars + leader lines, portals filling a third of the screen |
| Rainbow palette | 8 hues per frame; the ability bar alone is 6 colours |
| Stacked filters | chromatic aberration fringing every label red/cyan, grain over it, bloom on everything |
| Noise floors | "wear fields", "blotches", "mottle", "drag marks" — texture noise, not readable ground |
| Boxes around boxes | HUD = 9 separate plated panels |

The opposite of slop is not "more polish". It is **hierarchy, coherence, and
restraint** — the look of *Celeste*, *Hyper Light Drifter*, *Katana ZERO*,
*Eastward*. Most of their screen is quiet so the important 10% can sing.

---

## LAW 1 — One pixel grid

Every world-space pixel is exactly **2x2 screen pixels** at 1080p.

- All world sprites/tiles/props: `scale = Vector2(2.0, 2.0)` exactly, or 1.0 for
  art authored at 64px. **No 2.2, 2.5, 1.9, 0.5.** Grep for them and fix them.
- `rendering/2d/snap/snap_2d_transforms_to_pixel = true` and
  `snap_2d_vertices_to_pixel = true` in project.godot.
- Positions of static world objects are **even integers** (multiples of 2).
- No rotation of pixel sprites (rotation breaks the grid). Tokens **bob**, they
  do not spin. Portals may animate via shader only.
- VFX tweens may scale freely (they are transient); static art may not.
- Text: aliased. In `game_theme.gd`, derive the UI font from the default font
  with `antialiasing = TextServer.FONT_ANTIALIASING_NONE`,
  `hinting = TextServer.HINTING_NONE`, `subpixel_positioning =
  TextServer.SUBPIXEL_POSITIONING_DISABLED`, and use it everywhere via the
  theme's default font. Sizes: 14 (small) / 18 (body) / 26 (heading) only.
  Crisp aliased text reads as pixel text. Smooth text on pixel art reads as slop.

## LAW 2 — Three hues per scene

Each region gets exactly: **BASE** (the dark), **ACCENT** (the one neon), **WARM**
(a complementary glow). Nothing else saturated. Everything not in these three is
desaturated toward grey.

| region | BASE | ACCENT | WARM |
|---|---|---|---|
| localhost | #0E0C14 | #24F0DC cyan | #FFB74A amber (lamps, monitors) |
| dependency_district | #0A120C | #A8FF3E acid | #E08A3C crate orange |
| stackoverflow_ruins | #14110C | #E8C46B gold | #C97B4A copper |
| api_bazaar | #140A12 | #FF2D95 magenta | #FFD34D gold |
| cloud_district | #0A0E16 | #6BC7FF sky | #E8F4FF white |
| open_source_wildlands | #0A120E | #58E07C leaf | #C9A24A lantern |
| corporate_enterprise | #0B0E16 | #4D7CFF corp blue | #93A7C8 glass grey |
| gpu_mines | #140A08 | #FF6B2D ember | #FF3D2D heat |
| production | #14080A | #FF4757 red | #FFB020 amber |
| token_vault | #14100A | #FFD34D gold | #8B5CF6 violet |

Global constants (shared across regions, used sparingly): **GOLD #FFD34D** for
tokens/currency only; **HOSTILE #FF4757** for enemy tells only; **TEXT #D8DEEA**
and **TEXT_DIM #7C8BB0**. Enemies do NOT each get their own rainbow colour —
they read as hostile by silhouette + one red tell (eyes, core), body in
desaturated region tones.

The UI uses **one accent**: the region ACCENT for the world-linked elements
(objective, waypoint), and neutral TEXT/TEXT_DIM for everything else. The
ability bar is monochrome — six identical small slots, the ready one lit in
ACCENT, the rest TEXT_DIM. Not six colours.

## LAW 3 — Hierarchy: five things may be bright

Per frame, the only things allowed at full brightness / emissive:
1. the player
2. the current objective (waypoint chevron + its target)
3. tokens (small, gold)
4. at most **two** motivated light sources (a monitor bank, a lamp, a portal)
5. enemy tells (eyes/core only)

Everything else is ≤ 60% value. Props do not glow. Signs do not glow. Floors do
not glow. If you cannot say which of the five a bright pixel belongs to, it is
too bright.

## LAW 4 — Quiet by default: budgets per region

| thing | budget | now |
|---|---|---|
| tokens on the map | **6–10**, placed intentionally (near props, along the path, one cluster as a reward) | 25 scattered |
| world labels | **≤ 4**, wayfinding first (`EXIT →`, the NPC's name, one set-piece caption). Jokes live in prop interactions, not ambient signage | 21–34 |
| label style | plain aliased text, 1px `#000000@80%` drop shadow offset (1,1). **No plate, no accent bar, no leader line, no rounded rect.** Region ACCENT for wayfinding, TEXT_DIM for captions | plates+bars+lines |
| PointLight2D | **≤ 6**, energy 0.4–0.9, large soft radius. Lights pool on the floor; they do not spot-halo props | many |
| particle emitters | **≤ 2**: one ambient dust layer (≤ 16 particles, slow, TEXT_DIM at 25% alpha), one at the region's single set-piece | many |
| portal | 48px world-space (96 screen px), soft swirl, light energy 0.5, no halo ring. It should be *findable*, not *dominant* | huge + halo |
| floor overlays | **zero.** Remove mottle / wear field / blotches / drag marks / grime scatter. The floor is the tile art, with **one** hand-placed AO strip along walls and **≤ 3** decals per region | noise |
| set dressing | one focal set-piece per region, clearly lit; ≤ 8 secondary props; the rest is clean floor | dense scatter |

## LAW 5 — Post-processing is invisible

- **Chromatic aberration: 0.** Remove it. It smears every glyph.
- **Grain: ≤ 0.012.** Barely there.
- **Vignette: 0.14**, wide plateau. Never darker than that.
- **Bloom:** threshold **1.0** (only genuinely overbright pixels), 2 levels max,
  intensity ≤ 0.45. Bloom is for the five bright things in LAW 3 only.
- **Scanlines: 0.** Colour grade: neutral. Region mood comes from the ambient
  CanvasModulate and the ACCENT/WARM lights, not from a filter.
- Heat haze, code rain, god rays: **off by default.** One region may keep one
  atmosphere shader if it is subtle enough that a viewer would not name it.

## LAW 6 — Floors are readable ground

A floor tile is a **clean 32px material** with 3 tones (base, seam, highlight),
tiling seamlessly, with at most one subtle inset detail on ~10% of tiles. The A/B
variant differs by **≤ 6%** value. No hash-noise plates, no bevelled-everything,
no per-plate jitter above 3%. The player must be able to read the ground and
the walkable path at a glance.

## LAW 7 — One sprite language

All characters, enemies and props share one drawing language:
- 1px outline in `#0A0C16` at 90% alpha, full silhouette.
- 3 tones per material (shadow, base, light), light from top-left. A 4th "rim"
  tone only on the player.
- No dithering on anything smaller than 24px.
- Emissive pixel: **one** WHITE_HOT core pixel per light source on the sprite
  (an eye, an LED, a screen) — not a halo pass, not a glow pass, not rim glow.
- Enemies: hostile by silhouette. Body in desaturated region tones, exactly one
  red tell. No multi-hue noise, no per-enemy rainbow.
- Props: desaturated toward the region BASE; only screens/lamps carry ACCENT or
  WARM, and only on their lit surface.

## LAW 8 — UI is a single quiet layer

- **One HUD strip, no plates.** Top-left: `65 tk · 20 cp` in aliased body text
  with a drop shadow, directly on the world. Top-right: HP and Focus as two thin
  bars (4px, no border, no label chip). Top-centre: region name only, heading
  size, TEXT. No cycle/model readout box — fold `Cycle 1 · 149s` into small
  TEXT_DIM under the region name.
- **Objective: one line** at bottom-left, ACCENT, body size, drop shadow:
  `→ Talk to Claude · 4m NE`. No panel, no checklist on the HUD (the checklist
  lives in [J]).
- **Ability bar:** six 28px squares, 1px TEXT_DIM border, key glyph inside,
  ready = ACCENT border + ACCENT glyph, on cooldown = a vertical sweep. No
  names, no costs (hover/[H] shows them). Monochrome.
- **Minimap: removed.** The waypoint chevron is the navigation. Compass strip
  only if it costs nothing visually.
- **Toasts:** one line, TEXT, slides up from the bottom-centre, no box.
- **Modal screens** (menu, Dream App, quest log, map, pause, dialogue, death,
  victory, guide): one panel style — BASE at 96%, 1px LINE border, radius 0 or
  2, **no glow, no shadow, no sheen, no gradient**. One ACCENT per screen for
  the title and the primary action. Body in TEXT. Aliased font. Generous
  whitespace. Fewer words on screen at once.
- The **main menu**: skyline with ≤ 60 lit windows in WARM + ACCENT only (not
  confetti), a properly drawn moon (crisp disc, one crater tone), the coder at
  the desk lit by one monitor. Panel per the modal rule. Tip line in TEXT_DIM.

## LAW 9 — Motion is small

Tokens bob 2px. Characters breathe 1px. The waypoint pulses 0.9→1.0. Lights
flicker ±6%. Nothing else moves at rest. Combat may be loud; rest may not.

## LAW 10 — Comedy density

Jokes stay in dialogue, prop interactions, events, quest text, death/victory —
places the player *chooses* to read. They leave ambient world signage. A player
walking through a region sees at most 4 labels; the other 30 jokes are still in
the game, behind [E].

---

## Definition of done (the critic's rubric)

A frame passes if a cold viewer would answer YES to all of:
1. Can I tell in one second what is the player, what is the goal, and where the
   exits are?
2. Are there ≤ 3 saturated hues on screen?
3. Is every pixel the same size?
4. Is the text crisp with no colour fringing?
5. Is at least 60% of the frame visually quiet?
6. Could this be a screenshot from a shipped indie game?
