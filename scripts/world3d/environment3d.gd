extends RefCounted
## THE GRADE — VISUAL_BIBLE_V2 in one Environment.
##
## One WorldEnvironment for the whole game; this file is the only thing that
## writes it. `build()` makes the Environment the world scene mounts, and
## `apply_region()` re-tints it (and the moon) from the region's BASE and ACCENT
## on every region entry. Nothing else in the 3D layer may touch `Environment`
## fields — a second writer is how a room ends up with two moods.
##
## NO `class_name`. `World3D` is a real Godot class (the 3D scenario resource)
## and `Environment` is a real Godot class; the whole family is close enough to
## engine identifiers that a `class_name` here buys convenience and risks a
## silent, fatal collision. World3D preloads this file instead (same track, so
## a preload is safe).
##
## ------------------------------------------------------------------ ROUND 2 --
##
## v1 of this file implemented 3D_BIBLE.md §7 literally and produced the frames
## in docs/screenshots/qa3d: a washed pastel with no blacks, no hierarchy and no
## night. VISUAL_BIBLE_V2 supersedes §7 wherever the two disagree, and it
## disagrees here in four measurable places. Each is a named constant below:
##
##   1. EXPOSURE 1.05 -> 0.88. ACES lifts the MIDS (linear 0.18 comes out at
##      0.30), so an above-unity exposure on top of it pushed every mid-tone
##      into pastel. LAW 5. (It does NOT lift the darks — see EXPOSURE.)
##   2. GLOW intensity 0.9 -> 0.40, bloom 0.12 -> 0.03, levels 2-5 -> 2-3. LAW 5
##      caps bloom at 0.45 over two levels; the wide skirt was smearing the
##      whole frame, not just the five bright things LAW 3 allows.
##   3. VOLUMETRIC FOG: OFF. It was EMITTING the region accent (emission_energy
##      0.15 * accent) into 24u of air between the rig and the floor — a
##      full-frame colour wash by another name, which is exactly what LAW 5's
##      "colour grade: neutral" and LAW 2's "three hues" forbid. There is no
##      density at which an emitting fog is invisible, so the pass is gone
##      rather than dialled down.
##   4. AMBIENT energy 0.35 -> 0.20, in a cool colour pulled toward the region
##      BASE. The old ambient lit every face the moon missed, which is why
##      nothing in the old frames had a dark side. The moon is the main light
##      now (see `setup_moon`); the ambient only keeps a back-facing surface
##      from going to absolute black.
##
## Plus the void fix: the background is the region's BASE hex, not near-black,
## so the ground beyond a Kenney room's open edge reads as deep wall rather than
## as a hole punched in the frame (see `void_color`).
##
## ------------------------------------------------------------------ ROUND 3 --
##
## The review of round 2 did the light arithmetic against the floors the
## builders ACTUALLY author (region_builder3d.gd: the multimesh floor's albedo
## is the LAW 6 hex itself — `_floor_tint` divides by FLOOR_ALBEDO_REF and the
## matte override multiplies it straight back), not against a bare Kenney tile.
## Under round 2's moon (0.65, and a saturated blue) a #3E4A36 floor rendered at
## ~17/255 luminance — darker than the 32-41 that HANDOVER §4.12 already calls
## void. The fix is the moon, not the floor: MOON_ENERGY 0.65 -> 1.9 and a
## desaturated colour, which lands the authored 64-84 tile at 64-70 on screen.
## The derivation is at MOON_ENERGY; nothing else in the grade moved.

## VISUAL_BIBLE_V2 LAW 2 — the ACCENT column. COPIED verbatim from world.gd
## rather than imported: 3D_BIBLE.md §7 says "copy world.gd's REGION_ACCENT
## table, do not import it", so a parse error in the 2D world script can never
## take the 3D lighting down with it. If world.gd's table moves, move this one.
const REGION_ACCENT := {
	"localhost": Color("#24F0DC"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}
## The accent a region with no entry gets (BLUE, VISUAL_BIBLE master palette) —
## the same fallback world.gd hands its starfield.
const DEFAULT_ACCENT := Color("#3D9BFF")

## VISUAL_BIBLE_V2 LAW 2 — the BASE column, verbatim. BASE is "the dark — walls,
## shadow, out-of-bounds; NOT the floor" (LAW 6 says so twice, because pass 2
## made the mistake of painting floors with it). In this file BASE has exactly
## two jobs: it is the background the void is painted in, and it is the hue the
## ambient fill leans toward so a shadow side agrees with the room it is in.
const REGION_BASE := {
	"localhost": Color("#0E0C14"),
	"dependency_district": Color("#0A120C"),
	"stackoverflow_ruins": Color("#14110C"),
	"api_bazaar": Color("#140A12"),
	"cloud_district": Color("#0A0E16"),
	"open_source_wildlands": Color("#0A120E"),
	"corporate_enterprise": Color("#0B0E16"),
	"gpu_mines": Color("#140A08"),
	"production": Color("#14080A"),
	"token_vault": Color("#14100A"),
}
## The BASE a region with no entry gets: the neutral cool dark the ten table
## entries all sit within a few points of.
const DEFAULT_BASE := Color("#0B0D14")

## --- the grade ---------------------------------------------------------------

## LAW 5. ACES with an exposure UNDER one.
##
## What the curve actually does, because round 2 had it backwards: Godot's ACES
## is the RRT/ODT fit with an exposure_bias of 1.8, normalised by the tonemapped
## white point (0.781 at white = 1.0). It is an S-curve. Its slope at black is
## 1.8 * (A/E) / 0.781 = 0.24 — a TOE that crushes the darks — and it only lifts
## above about 0.055 linear (~65 sRGB): 0.18 linear comes out at 0.30. So the
## exposure is not what makes a floor dark; the key light is (see MOON_ENERGY).
## What the exposure decides is where the pastel starts: §7's 1.05 pushed every
## mid-tone up the lifting half of the curve, which with 22 omnis and an
## emitting fog is docs/screenshots/qa3d. 0.88 keeps a little headroom under the
## shoulder so a lamp pool is a pool and not a white disc, and leaves the
## glow threshold (1.0) reachable only by things that are actually emissive.
const EXPOSURE := 0.88

## LAW 5: "threshold 1.0 (only genuinely overbright pixels), 2 levels max,
## intensity <= 0.45". All three obeyed, with the intensity a notch under the
## cap: the bloom must be findable only on the things that earned it.
const GLOW_INTENSITY := 0.40
## Bloom is the amount of the UNDER-threshold image that leaks into the blur.
## 0.12 leaked the whole frame; at 0.03 only pixels already at the threshold
## contribute, which is what "bloom is for the five bright things" means in a
## number.
const GLOW_BLOOM := 0.03
const GLOW_THRESHOLD := 1.0

## LAW 5 again, from the other side: the ambient is a FILL, not a light. Low
## enough that a face the moon misses stays dark (that darkness is two of
## Kenney's three tones), high enough that the silhouette does not fuse into the
## background. At 0.20 it is ~2% of the moon's gain on a floor, and it cannot
## be the thing that fills a shadow: ACES's toe (see EXPOSURE) sends anything
## under ~0.01 linear to black whatever the fill is, so a back-facing wall is a
## silhouette at 0.20 and still a silhouette at 0.35. What lifts a shadow is
## MOON_SHADOW_OPACITY.
const AMBIENT_BASE := Color(0.40, 0.46, 0.60)
const AMBIENT_ENERGY := 0.20
## How far the fill leans from that cool grey toward the region's BASE. LAW 2:
## everything that is not BASE/ACCENT/WARM is desaturated, and the fill is the
## most everywhere thing in the frame, so it leans toward the DARK of the room
## and never toward its neon.
const AMBIENT_TINT := 0.30

## SSAO, subtle. This is the single biggest reason Kenney's flat colormap reads
## as geometry rather than as a sticker sheet: every inside corner in the kit
## gets a contact shadow the albedo does not have. §7 asked for intensity 2.0,
## which at the old exposure was the only contrast in the frame and read as
## dirt; 1.2 is the same effect under a grade that now has its own blacks.
const SSAO_INTENSITY := 1.2
const SSAO_RADIUS := 1.0

## --- the void ----------------------------------------------------------------

## How far the BASE hex is lifted before it is handed to the background.
##
## THIS IS A PRE-COMPENSATION, NOT A TASTE. The background colour is converted
## sRGB -> linear on its way into the HDR buffer and then comes back out through
## the ACES toe at EXPOSURE (see there: slope 0.24 at black), so painting the raw
## hex would DISPLAY far darker than the hex: #0A120C (18/255 green) round-trips
## to about 4/255, which IS black — the exact hole visible on the left of
## combat_dependency_district.png and the top-right of
## region_dependency_district.png. Lifting the input by 0.055 (to ~31/255 green)
## brings the DISPLAYED colour back to within a few points of the hex itself,
## roughly (8, 15, 9) for dependency_district: the region's own BASE on screen,
## unmistakably deep wall, and never a hole. Walls the moon catches land in the
## same band (~16), which is what makes the surround read as more wall.
const VOID_LIFT := 0.055

## --- the moon ----------------------------------------------------------------

## The main light. Kenney's flat colormap has no shading of its own, so the
## three tones a low-poly prop shows — lit top, mid side, dark side — are
## entirely this light's doing, and a directional light is the only one that can
## give the same three tones to every prop in the room at once. The per-region
## OmniLights are POOLS (LAW 3's "at most two motivated light sources"), not
## fill; when they were doing the lighting the room had 22 of them.
##
## WHY 1.9 AND NOT §7's 0.4 (or round 2's 0.65). Godot's non-physical lights are
## unit-gain: an upward face with albedo A under a directional light of energy E
## and linear colour C renders A * C * E * NdotL. The builders author the floor's
## albedo AT the LAW 6 hex (region_builder3d.gd `_floor_tint` / the matte
## override), and LAW 6 wants that hex ON SCREEN, so the moon's gain on the
## floor times EXPOSURE has to be about 1.0. With NdotL = sin 50 = 0.766 and the
## green of MOON_BASE at 0.746 linear, 0.746 * 0.766 * 1.9 * 0.88 = 0.96: a
## #3E4A36 floor displays at ~(50, 76, 59) = luminance 69, the localhost planks
## at ~64, both inside 64-84. At 0.65 the same floors rendered at ~17/255.
##
## THE COLOUR IS DESATURATED ON PURPOSE. Round 2's (0.62, 0.72, 1.0) is 38%
## saturated blue, which put a 2.3:1 blue-to-red cast on every neutral surface:
## a fourth hue in every room (LAW 2). (0.82, 0.88, 1.0) is 18% — still cool,
## still a moon, and the wood in localhost keeps its warmth under it.
const MOON_BASE := Color(0.82, 0.88, 1.0)
const MOON_ENERGY := 1.9
const MOON_PITCH_DEG := -50.0
const MOON_YAW_DEG := 30.0
## Soft PCF. The rig sees a ~25u x 21u patch of ground from ~24u up, so the
## farthest shadow caster is about 35u from the camera; 60u of parallel splits
## covers that with the resolution to spare that a blur this wide wants.
const MOON_SHADOW_DISTANCE := 60.0
const MOON_SHADOW_BLUR := 2.0
## Under 1.0 so a shadowed floor is dark, not black — the ambient is only 0.20
## and cannot lift it on its own (see AMBIENT_ENERGY). Sized against the ACES
## toe, not by eye: at 0.85 a moon-shadowed #3E4A36 floor displays at ~11/255,
## a black cut-out darker than LAW 6's own seams; at 0.65 it displays at ~28,
## about 41% of the lit floor — one step under the seam band (36-48), so a cast
## shadow is the darkest floor tone there is and still reads as floor.
const MOON_SHADOW_OPACITY := 0.65
## A whisper, and deliberately smaller than the ambient's: the moon is the one
## thing in the frame that is the same in every region, and a moon that changed
## hue per room would be ten moons. Small enough that a viewer could not name it,
## large enough that a region entry agrees with itself.
const MOON_TINT := 0.08

## --- lookups -----------------------------------------------------------------

## The region's neon, or the palette's BLUE.
static func accent(region_id: String) -> Color:
	return REGION_ACCENT.get(region_id, DEFAULT_ACCENT)

## The region's dark, or the neutral cool dark.
static func base_color(region_id: String) -> Color:
	return REGION_BASE.get(region_id, DEFAULT_BASE)

## The background the void is painted in, for a region BASE. See VOID_LIFT for
## why this is not simply `base`. Alpha forced opaque: a background Color with
## alpha is a background nobody chose.
static func void_color(base: Color) -> Color:
	var c := base.lightened(VOID_LIFT)
	c.a = 1.0
	return c

## The ambient fill for a region BASE: the cool grey leaned AMBIENT_TINT of the
## way toward the room's own dark.
static func ambient_color(base: Color) -> Color:
	var c := AMBIENT_BASE.lerp(base, AMBIENT_TINT)
	c.a = 1.0
	return c

## True on a backend that can actually run SSAO. The web export is
## `gl_compatibility` (project.godot), where it is a no-op — asking for it there
## costs nothing visually and confuses anyone reading the scene, so we do not.
static func _has_rd() -> bool:
	return RenderingServer.get_rendering_device() != null

## Graphics quality, defensively: SettingsManager returns Variant and a save
## from an older build can hold anything. Public because world3d.gd gates the
## viewport's MSAA on the same number and the two must not drift.
static func quality() -> int:
	var q: Variant = SettingsManager.get_setting("graphics_quality")
	return int(q) if (q is int or q is float) else 1

## --- build -------------------------------------------------------------------

## The Environment the world mounts on its WorldEnvironment. Region-independent
## parts only; `apply_region()` writes the rest and must be called at least once
## before the first frame the player sees.
static func build() -> Environment:
	var env := Environment.new()
	# `q` and not `quality`: a local named after the static function shadows it,
	# and GDScript resolves the name to the local on the same line it is declared.
	var q := quality()
	var rd := _has_rd()

	# The void outside the room, in the DEFAULT region's dark until
	# `apply_region()` names one. Never pure black (that is the hole) and never
	# bright (that is a fifth hue).
	env.background_mode = Environment.BG_COLOR
	env.background_color = void_color(DEFAULT_BASE)
	env.background_energy_multiplier = 1.0

	# Flat-colormap models have no environment to bounce off, so this is their
	# only fill. It is a floor under black, not a light — see AMBIENT_ENERGY.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color(DEFAULT_BASE)
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ambient_light_sky_contribution = 0.0

	# ACES under one. The emissive screens and signs are authored well over 1.0
	# so a filmic shoulder is still what stops them clipping to white discs; the
	# exposure is what stops everything else joining them (see EXPOSURE).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.0
	env.tonemap_exposure = EXPOSURE

	_apply_glow(env)
	_apply_ssao(env, q, rd)

	# NO ATMOSPHERE, of either kind (LAW 5: "heat haze, code rain, god rays: off
	# by default"; LAW 2: three hues). Depth fog greys out the accent;
	# volumetric fog was worse — it was emitting the accent through 24u of air
	# between the rig and the floor, which is a full-frame colour grade wearing
	# a physical name. Both off, explicitly, so neither is ever a setting nobody
	# chose.
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false

	# NO COLOUR GRADE (LAW 5). v1 kept "a whisper of contrast" here — contrast
	# 1.04, saturation 1.05 — and a whisper applied to every pixel in the frame
	# is still a filter. The mood is the light now.
	env.adjustment_enabled = false
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	return env

## LAW 5 glow: threshold 1.0 so only genuinely overbright pixels (the emissive
## signs, the omni cores, the portal) bloom at all, SOFTLIGHT so the bloom tints
## rather than washes, and TWO levels — the tight ones.
##
## Every level is written: Godot's defaults are not all zero (3 and 5 are on),
## so an unwritten level is a level nobody chose — the exact trap world.gd
## documents for the 2D pass. Levels 4 and 5 are the wide skirt that made the
## old frames glow as a whole instead of glowing at the lamps, and they are off
## at every quality now rather than off only on low.
static func _apply_glow(env: Environment) -> void:
	env.glow_enabled = true
	env.glow_intensity = GLOW_INTENSITY
	env.glow_strength = 1.0
	env.glow_bloom = GLOW_BLOOM
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_hdr_scale = 2.0
	for level: int in range(0, 7):
		env.set_glow_level(level, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)

## SSAO, on where the device can run it. Subtle (SSAO_INTENSITY), and kept off
## the direct light: the emissive props are the five bright things LAW 3 allows,
## and occlusion over direct light would dim them in exactly the corners they
## are placed in.
static func _apply_ssao(env: Environment, q: int, rd: bool) -> void:
	var want := rd and q >= 1
	env.ssao_enabled = want
	if not want:
		return
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0

## --- per region --------------------------------------------------------------

## Re-tint the room for `region_id`. Called on every region entry, including the
## first. Safe with a null moon (a test rig that mounts only an Environment) and
## with a null env (a WorldEnvironment whose resource has not been built yet).
##
## Three writes, and only three: the void, the fill and the moon's hue. Nothing
## here touches exposure, glow or SSAO — those are the GRADE, and a grade that
## changed per room would be ten grades.
static func apply_region(env: Environment, moon: DirectionalLight3D, region_id: String) -> void:
	var b := base_color(region_id)
	var a := accent(region_id)
	if env != null:
		env.background_color = void_color(b)
		env.ambient_light_color = ambient_color(b)
	if moon != null:
		setup_moon(moon)
		moon.light_color = MOON_BASE.lerp(a, MOON_TINT)

## The one directional light. Idempotent — apply_region() calls it on every
## region entry so a moon that some other system nudged comes back to spec.
##
## This is the "Kenney's flat colours read with depth" half of the look, and
## after round 2 it is also most of the light in the room. A 4-split parallel
## shadow at 60u covers everything the rig can see, the blur softens the hard
## kit edges into something that looks lit rather than stencilled, and
## `shadow_opacity` under 1.0 keeps a shadowed face readable — the ambient
## alone cannot lift it, because it is deliberately only 0.20.
static func setup_moon(moon: DirectionalLight3D) -> void:
	if moon == null:
		return
	moon.light_color = MOON_BASE
	moon.light_energy = MOON_ENERGY
	moon.light_specular = 0.15
	moon.light_angular_distance = 1.2
	moon.light_bake_mode = Light3D.BAKE_DISABLED
	# Rotation, not look_at: the moon has no target and a look_at from the
	# origin would flip whenever the rig crossed it.
	moon.rotation = Vector3(deg_to_rad(MOON_PITCH_DEG), deg_to_rad(MOON_YAW_DEG), 0.0)
	moon.shadow_enabled = quality() >= 1
	moon.shadow_bias = 0.03
	moon.shadow_normal_bias = 1.0
	moon.shadow_blur = MOON_SHADOW_BLUR
	moon.shadow_opacity = MOON_SHADOW_OPACITY
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = MOON_SHADOW_DISTANCE
	moon.directional_shadow_blend_splits = true
	moon.directional_shadow_fade_start = 0.85
	moon.directional_shadow_pancake_size = 20.0
