> **Superseded in part by VISUAL_BIBLE_V2.md (Restraint). Where they conflict, v2 wins.**

# VISUAL BIBLE — "Neon Afterhours" (authoritative art direction)

Every visual change in this overhaul conforms to this document. It is the
single contract between subsystems. Read fully before writing code.

## Vision

Cinematic cyberpunk pixel-art. The world is a dim, humming machine at 3am —
deep indigo darkness carved by neon light. Every light source GLOWS (HDR
bloom is on). Surfaces are shaded, worn, and inhabited. Nothing is a flat
ColorRect. The screen itself has atmosphere: grain, vignette, subtle
chromatic fringing. Think *Hyper Light Drifter* meets *Katana ZERO* meets a
server room at night.

## Master palette

| Token | Hex | Use |
|---|---|---|
| VOID | #05060E | outside-the-world background |
| BASE | #0B0E1C | darkest floor/room base |
| SURFACE | #131A2E | mid surfaces |
| RAISED | #1C2440 | raised furniture/props base |
| LINE | #2A3558 | seams, outlines on props |
| TEXT_DIM | #7C8BB0 | secondary UI text |
| TEXT | #C9D6F2 | primary UI text |
| WHITE_HOT | #F4F9FF | hottest emissive core |
| CYAN | #24F0DC | primary neon (abilities, UI accent) |
| CYAN_HOT | #7DFFF0 | cyan emissive core |
| MAGENTA | #FF2D95 | secondary neon (danger-adjacent, signs) |
| VIOLET | #8B5CF6 | arcane/AI accents |
| BLUE | #3D9BFF | info, water, cloud |
| ACID | #A8FF3E | dependency green |
| AMBER | #FFB020 | warmth, warnings, coffee |
| RED | #FF4757 | damage, production incidents |
| GOLD | #FFD34D | tokens, currency |

## Per-region accent palettes (region_id -> primary / secondary / atmosphere tint)

| region | primary | secondary | ambient CanvasModulate |
|---|---|---|---|
| localhost | AMBER #FFB74A | CYAN #24F0DC | warm dim (0.72,0.68,0.78) |
| dependency_district | ACID #A8FF3E | crate #E08A3C | green-dark (0.62,0.72,0.62) |
| stackoverflow_ruins | gold #E8C46B | copper #C97B4A | dusty (0.70,0.66,0.58) |
| api_bazaar | MAGENTA #FF2D95 | GOLD #FFD34D | pink night (0.72,0.60,0.74) |
| cloud_district | sky #6BC7FF | white #E8F4FF | cool bright (0.72,0.78,0.88) |
| open_source_wildlands | leaf #58E07C | moss #3E9E5C | verdant (0.62,0.76,0.66) |
| corporate_enterprise | corp #4D7CFF | glass #93A7C8 | sterile (0.68,0.72,0.82) |
| gpu_mines | ember #FF6B2D | heat #FF3D2D | hot dark (0.78,0.58,0.52) |
| production | RED #FF4757 | AMBER #FFB020 | alarm dim (0.80,0.56,0.58) |
| token_vault | GOLD #FFD34D | VIOLET #8B5CF6 | rich dark (0.74,0.68,0.56) |

## HDR glow techniques (project has hdr_2d=true + Environment glow)

PNGs are 8-bit — a pixel can't exceed 1.0. To make things BLOOM:
1. **Overbright modulate**: duplicate an emissive sprite/element and set
   `modulate = Color(c.r*2.2, c.g*2.2, c.b*2.2)`; values >1 push into HDR.
2. **Additive material**: `var m := CanvasItemMaterial.new();
   m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; node.material = m`
3. **PointLight2D** with `energy` 0.9–1.6 and a soft radial texture.
Near-white pixels (>= 0.9) bloom on their own — use WHITE_HOT cores inside
neon details in generated art.

## Shader library — assets/shaders/ (ALREADY WRITTEN — use, don't rewrite)

| file | apply to | key uniforms |
|---|---|---|
| postfx.gdshader | full-screen ColorRect (screen-reading) | intensity, vignette_strength, aberration, grain_amount, scanline_amount, grade_lift/gamma |
| crt_monitor.gdshader | in-world monitor/screen sprites | scan_density, flicker_speed, glow_boost |
| neon_flicker.gdshader | neon sign sprites/labels | seed, base_boost, flicker_amount |
| portal_swirl.gdshader | portal sprite (any square texture) | hue_color, speed, arms |
| hologram.gdshader | holographic NPCs/props | tint, scan_speed, alpha_base |
| dissolve.gdshader | enemy death (set progress 0->1 in tween) | progress, edge_color, pixel_size |
| heat_haze.gdshader | ColorRect over hot regions (screen-reading) | strength, speed |
| code_rain.gdshader | ColorRect overlay, matrix rain | tint, columns, speed, alpha_max |
| starfield.gdshader | large ColorRect behind world (void bg) | base_color, accent_color, scroll (bind camera pos *0.05), density |
| ui_sheen.gdshader | UI panels — moving diagonal highlight | sheen_color, period, width |

Usage pattern:
```gdscript
var mat := ShaderMaterial.new()
mat.shader = load("res://assets/shaders/portal_swirl.gdshader")
mat.set_shader_parameter("hue_color", Color("#8B5CF6"))
node.material = mat
```
ALWAYS guard optional textures with `ResourceLoader.exists(path)`.

## Generated-asset manifest (produced by the pixel-art agents; consumers MUST exists()-guard)

- `fx_radial_soft.png` 128x128 radial falloff (light cookie / soft glow)
- `fx_glow_dot.png` 16x16 soft dot (particles, sparks)
- `fx_spark.png` 8x8 hard spark
- `decal_grime_0.png`..`decal_grime_2.png` 64x64 translucent floor grime
- `decal_ao_edge.png` 32x32 vertical gradient (black->transparent) for wall-base ambient occlusion strips

## Pixel-art quality bar (generators)

- 4-tone shading minimum per material: shadow / base / light / rim.
  Light source is TOP-LEFT, consistent everywhere.
- 1px dark outline (#0A0C16 at ~85% alpha) on characters/enemies/props.
- Rim light on the top-left silhouette edge in the region/character accent color.
- Selective dithering (2x2 checker) on large gradients — never flat fills > 8px.
- Emissive details get a WHITE_HOT core pixel + accent halo pixel around it.
- Floor tiles: per-tile hash jitter in value (±4%), occasional variant details
  (vents, cables, cracks, glyphs) at ~8% of tiles. Kill visible tiling.
- Tiles must tile seamlessly; test edges mentally — no border artifacts.

## Lighting rules (builders)

- Every emissive prop (monitor, sign, server LED, portal, token cluster) gets a
  PointLight2D: soft radial texture, energy 0.5–1.4, scale to purpose.
- Flicker: animate a few lights per region via Tween/sin — subtle (±10% energy).
- Player carries a soft light (energy ~0.55, large radius, warm white).
- CanvasModulate uses region ambient tint (table above) — the world must feel
  DARK so lights matter, but gameplay stays readable.

## Particle budget (per region)

- Max ~12 emitters, prefer CPUParticles2D, <= 40 particles each.
- Layers: (a) region-themed ambient (embers/spores/data/rain), (b) foreground
  dust motes drifting through light, subtle, (c) point-of-interest accents.

## UI style tokens

- Panels: BASE bg at 92% alpha, 1px LINE border + outer glow (add a 2nd
  slightly larger panel behind with accent color at 8% alpha), corner radius 6.
- Accent per screen: CYAN (default), RED (death), GOLD (victory/tokens).
- Bars: gradient fill (accent -> accent_hot), 1px WHITE_HOT top edge; animate
  changes with 0.25s EASE_OUT tween; damage flashes a trailing red segment.
- Buttons: transparent base, LINE border; hover = accent border + accent text
  + 4% accent bg; pressed = 12%. Focus ring in accent.
- Title text: letter-spaced, with a duplicated overbright glow layer.
- Animation timing: micro 0.12s, standard 0.25s, dramatic 0.6s; TRANS_CUBIC.

## Camera & juice standards

- Camera: position_smoothing 6.0; trauma-based shake (decay 2.2, max offset
  6px, noise-driven) — small kicks on hit (0.25), bigger on death (0.6).
- Hit-stop: 40ms Engine.time_scale dip on melee-range kills (guard: never
  while paused/dialogue).
- Pickups: scale-pop + fly-to-player magnet + burst of fx_glow_dot particles.
- Enemy death: dissolve.gdshader progress tween 0.45s + spark burst.

## Hard constraints

- Godot 4.7 GDScript, typed, TABS for indent, match existing style.
- Do NOT run godot (import-lock contention while agents work in parallel).
- Do NOT rename/remove existing node names, groups, scene paths, public
  functions, or texture filenames tests rely on. Additive or in-place edits.
- 60fps: no per-frame allocations in _process; reuse ShaderMaterials where
  identical (share one instance per shader+params combo when possible).
- Comedy tone: any new visible text stays dry-sarcastic (see COMEDY_BIBLE.md).

## Round 4 — Readability & Fidelity (addendum, authoritative for this round)

Verdict from the round-3 QA frames (docs/screenshots/qa/): the atmosphere is
strong but **composition and readability lag it**. Specific, evidenced gaps:

- `menu.png` — near-black screen with one floating panel. No motion, no place,
  no character. This is the first frame a judge sees.
- `region_gpu_mines.png` / `region_open_source_wildlands.png` — the ground is
  a uniform noise wash ("color soup"). No paths, no material zones, no reading
  of "walk here". Props under the world labels are dark smudges; the labels
  carry all the meaning their objects should.
- Focal set-pieces exist but do not command the frame; mid-ground and
  background sit at the same value level.

### Rules for this round (all world/art agents)

1. **Structure before noise.** Every region floor gets readable structure
   first — paths/pavement/plank runs/server-room panel grids/rock strata —
   then grime/noise ON TOP at <= 25% opacity. A player must see where to walk
   in a 1-second glance at a static frame.
2. **Silhouette law.** Every labeled prop reads WITHOUT its label at game
   zoom: >= 3 value steps, a 1px rim-light on the lit side, and a contact
   shadow. If the label is doing the work, the sprite failed.
3. **Contrast hierarchy.** One brightest thing per screen (the focal
   set-piece), mid-ground a step down, edges darkest. Full-screen wash shaders
   cap at the particle/lighting budgets above — never crush the hierarchy.
4. **Menu hero.** The menu becomes a scene: animated backdrop (parallax neon
   skyline through an apartment window, code-rain on a monitor glow), title
   with slow glow pulse, buttons with hover slide+glow, the player character
   silhouetted at a desk. Motion budget: subtle, 60fps, no strobing.
5. Additive only. The 15-shader uniform API is FROZEN (tune defaults, add new
   uniforms with safe defaults, never rename/remove). Texture filenames and
   node/group names stay.
