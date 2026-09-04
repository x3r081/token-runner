class_name RegionBuilder3D
extends RefCounted
## Builds the nine non-apartment regions in 3D from Kenney kits (3D_BIBLE.md
## §2.4, §7, §8, §9). Localhost has its own builder (LocalhostBuilder3D).
##
## THE AUTHORED LAYOUT IS NOT RE-AUTHORED HERE. Every position in a finished
## region — enemy posts, boss arenas, cover blocks, NPC anchors, portals,
## interactables, flavour props, token spots, the region's focal landmark, and
## even the plaza/artery zoning the floor is painted with — is read out of the
## 2D `RegionBuilder` statics. This file decides what a thing LOOKS like in
## three dimensions and nothing about where it stands. If a composition edit
## lands in region_builder.gd, this file inherits it for free; if you find
## yourself typing a Vector2 that already exists over there, stop.
##
## Physics is deliberately IDENTICAL to the 2D twin's: the only solids are the
## four border walls and the blocks in `_region_cover`. Set dressing does not
## collide — the same convention the 2D rooms use, and the one every
## navigability assumption in tests/region_arrival_test.gd and
## tests/region_winnable_test.gd was authored against.
##
## LOOK LAW: docs/VISUAL_BIBLE_V2.md, which supersedes 3D_BIBLE §7 wherever the
## two disagree — and they disagree about brightness everywhere. The pass that
## rewrote the colour half of this file was answering one measured defect: the
## QA frames had no blacks, no hierarchy and no night. Four rules carry it, and
## each is enforced in a helper rather than trusted to a call site, because
## every one of them was already "policy" and drifted anyway:
##
##   * `light()` — six omnis a region, energy 0.5-1.2, range 6-10 (LAW 3/4).
##   * `panel()` — the only emissive surfaces are screens, one focal face and a
##     fire, at energy 0.8-1.6 (LAW 3/7); signage stops at SIGN_E_MAX.
##   * `place()` — every prop is DESATURATED against its own measured swatch
##     (`_prop_target`), so only the three LAW 2 hues stay saturated, and SIZED
##     against its own measured bounds (`_cap`), so nothing outgrows the player.
##   * `_build_floor` — the ground is generated geometry at a chosen luminance
##     with an A/B tile pair, dark seams and one inset detail (LAW 6). REGION_
##     FLOOR is the mid-value ground, REGION_BASE is the dark, and the two are
##     never each other (LAW 6, and HANDOVER §4.12 on why that must be said).
##   * `_build_void` / `_build_backdrop` — the out-of-bounds ground is LIT and
##     BASE-coloured, and the only thing standing in it is one low, dark,
##     shadowless band (the pass-3 critic measured 17-21% of the frame as black
##     void with trees planted in it).
##
## Set dressing is budgeted at 24 secondary placements a region. It is not a
## number this file can enforce, only one it can be counted against; each
## `_dress_*` says its own arithmetic in a comment above the scatters.
##
## Scale law: every Kenney pack used here is authored at roughly 1 unit = 2 m,
## which is also 1 tile = 64 map px, which is also the 0.9u the bible sizes a
## character at. A desk is 1.0, a gravestone is 1.0, a wall is 1.0. When a
## prop wants a different size it is because the FICTION wants it bigger, not
## because the kit needed correcting.

## Map pixels per tile / per world unit. Mirrors RegionBuilder.TILE_SIZE and
## Map3D.PX; the whole file works in map px and converts at the call to place().
const PX := 64.0

## Physics layers (3D_BIBLE §8). Only walls and cover are solid here.
const L_WALLS := 32

## Fixed cross-track scene paths (3D_BIBLE §3/§4). Loaded with exists() guards
## because sibling tracks land these concurrently — a region missing its enemy
## scene must still build its room.
const SCENE_ENEMY := "res://scenes/world3d/enemy3d.tscn"
const SCENE_NPC := "res://scenes/world3d/npc3d.tscn"
const SCENE_PORTAL := "res://scenes/world3d/portal3d.tscn"
const SCENE_TOKEN := "res://scenes/world3d/token_pickup3d.tscn"
const SCENE_INTERACT := "res://scenes/world3d/interactable3d.tscn"

## VISUAL_BIBLE_V2 budgets, enforced rather than hoped for. Six omnis, not
## thirty-six: LAW 4 caps the room's light rig at six and LAW 3 says only two of
## them may be MOTIVATED sources on top of the focal. The old 36 was not a
## budget, it was a ceiling nobody could hit — and the frames proved it, because
## the rig that grew under it lit every face of every prop from every side and
## left the room with no blacks at all.
const MAX_LIGHTS := 6
const MAX_SHADOW_LIGHTS := 1

## LAW 3/4 light window. `light()` clamps into these rather than trusting call
## sites: an energy-5 omni at range 4 is a spot-halo on a prop, which is the
## exact defect LAW 4 names ("lights pool on the floor; they do not spot-halo
## props").
const LIGHT_E_MIN := 0.5
const LIGHT_E_MAX := 1.2
const LIGHT_R_MIN := 6.0
const LIGHT_R_MAX := 10.0
const LIGHT_ATTEN := 1.5

## LAW 3/7 emissive window. The only emissive surfaces this file may build are
## screens/monitors, the focal set-piece's ONE lit face, and a fire. `panel()`
## clamps to this so a call site cannot ask for the energy-7 slabs that turned
## every region into a light box.
## RE-SIZED after pass 3. At 2.4-3.0 a lit face clipped the ACES shoulder and
## came back WHITE — the critic counted "four separate blown-white emissive
## masses" in the Mines and "a flat pure-white rectangle on the floor at the
## base of every barrel" (they are the rack strips) in the Mines and Cloud. The
## glow threshold is 1.0, so 0.8-1.6 still blooms and is still the brightest
## thing in the room; it just reads as a COLOUR now instead of as a hole in the
## exposure. Nothing this file draws is white.
const PANEL_E_MIN := 0.8
const PANEL_E_MAX := 1.6

## Signage is dimmer again, because a sign is not a screen (LAW 3 says so twice)
## and the north-wall bank was blowing out behind the HUD's region title.
const SIGN_E_MAX := 1.2

## LAW 2 — BASE per region: the dark. Walls, shadow, out-of-bounds. NOT the
## floor (LAW 6, and HANDOVER §4.12: writing BASE onto the ground is what gave
## nine rooms of void). The void plane, the border ring and every backdrop
## silhouette are built out of this colour and nothing else.
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

## LAW 6 — the FLOOR material's base tone per region, sRGB. This is a MID-VALUE
## ground (luminance 64-84 on the bare tile), which is a different thing from
## BASE above and the distinction is the whole of gotcha 12.
const REGION_FLOOR := {
	"localhost": Color("#5A3F2A"),
	"dependency_district": Color("#3E4A36"),
	"stackoverflow_ruins": Color("#5C503C"),
	"api_bazaar": Color("#4C3244"),
	"cloud_district": Color("#404854"),
	"open_source_wildlands": Color("#404C32"),
	"corporate_enterprise": Color("#383E4E"),
	"gpu_mines": Color("#4E3C34"),
	"production": Color("#46464A"),
	"token_vault": Color("#605028"),
}

## What each Kenney model's albedo actually reads at before anything is done to
## it: the area-weighted mean of its base-colour texture (or flat factor) over
## every face it has, as sRGB. MEASURED from the GLBs, not assumed: a single
## "0.55" was the previous guess, and the kits disagree with it by a factor of
## four (retro-urban asphalt 0.23, mini-market floor 0.87) and in hue (nature's
## grass is a saturated cyan-green, the castle and cliffs are orange). A tint
## that divides by the wrong swatch lands the floor a stop off the LAW 6 hex in
## either direction, which is exactly the wash/void pair the QA frames showed.
##
## `_tint_to()` divides the TARGET by this in linear space, so the product the
## GPU computes (tint x texture) averages to the target exactly; the texture's
## own local variation survives as ratios around it. Keys not listed fall back
## to SWATCH_DEFAULT, a mid grey.
##
## RE-MEASURED for pass 3, and the table is now EVERY model this file places,
## not just its floors and walls — `place()` needs a model's own reading to
## desaturate it (see `_prop_target`). Two corrections came out of the re-measure
## and both were visible in the frames:
##   * the mean is taken in LINEAR light and reported as sRGB. A mean of sRGB
##     texels reads a textured model 20-35% brighter than it is, and dividing by
##     that landed the Corporate and Cloud decking a full stop under the LAW 6
##     hex — the critic measured 21-29 where the hex is 62.
##   * a model whose texture TILES (the whole retro-urban pack: asphalt.png,
##     concrete.png, 64x64 each) is read as the mean of the WHOLE texture; only
##     a colormap ATLAS can be sampled per-face.
const SWATCH := {
	"castle/flag": Color(0.628, 0.468, 0.629),
	"castle/metal-gate": Color(0.808, 0.815, 0.883),
	"castle/tower-hexagon-base": Color(0.902, 0.711, 0.564),
	"castle/tower-slant-roof": Color(0.703, 0.587, 0.677),
	"castle/tower-square-base": Color(0.907, 0.736, 0.598),
	"castle/tower-square-mid": Color(0.924, 0.748, 0.596),
	"castle/tower-square-top-roof-high": Color(0.658, 0.500, 0.611),
	"castle/wall": Color(0.889, 0.683, 0.537),
	"castle/wall-half": Color(0.889, 0.688, 0.543),
	"castle/wall-pillar": Color(0.887, 0.680, 0.534),
	"city-commercial/building-a": Color(0.559, 0.569, 0.632),
	"city-commercial/building-f": Color(0.564, 0.583, 0.645),
	"city-commercial/building-k": Color(0.531, 0.537, 0.599),
	"city-commercial/building-skyscraper-a": Color(0.567, 0.604, 0.705),
	"city-commercial/building-skyscraper-b": Color(0.585, 0.628, 0.738),
	"city-commercial/building-skyscraper-c": Color(0.616, 0.655, 0.739),
	"city-commercial/building-skyscraper-d": Color(0.627, 0.671, 0.759),
	"city-commercial/building-skyscraper-e": Color(0.662, 0.684, 0.748),
	"city-commercial/detail-awning": Color(0.329, 0.595, 0.503),
	"city-commercial/detail-parasol-a": Color(0.451, 0.617, 0.569),
	"city-commercial/detail-parasol-b": Color(0.445, 0.626, 0.568),
	"city-commercial/low-detail-building-a": Color(0.775, 0.778, 0.831),
	"city-commercial/low-detail-building-d": Color(0.851, 0.851, 0.899),
	"city-commercial/low-detail-building-g": Color(0.819, 0.821, 0.871),
	"city-commercial/low-detail-building-wide-a": Color(0.755, 0.759, 0.813),
	"city-industrial/building-a": Color(0.480, 0.495, 0.560),
	"city-industrial/building-c": Color(0.639, 0.597, 0.616),
	"city-industrial/building-h": Color(0.593, 0.599, 0.661),
	"city-industrial/building-j": Color(0.611, 0.621, 0.680),
	"city-industrial/building-m": Color(0.572, 0.572, 0.631),
	"city-industrial/building-q": Color(0.532, 0.546, 0.608),
	"city-industrial/building-t": Color(0.497, 0.514, 0.572),
	"city-industrial/chimney-large": Color(0.522, 0.466, 0.489),
	"city-industrial/chimney-medium": Color(0.794, 0.715, 0.704),
	"factory/box-large": Color(0.832, 0.518, 0.374),
	"factory/box-long": Color(0.836, 0.531, 0.387),
	"factory/box-wide": Color(0.830, 0.517, 0.373),
	"factory/catwalk-straight": Color(0.568, 0.506, 0.609),
	"factory/cog-a": Color(0.464, 0.464, 0.627),
	"factory/cog-b": Color(0.462, 0.462, 0.625),
	"factory/cog-c": Color(0.469, 0.469, 0.632),
	"factory/cog-d": Color(0.469, 0.469, 0.633),
	"factory/cog-e": Color(0.457, 0.457, 0.619),
	"factory/cone": Color(0.969, 0.602, 0.466),
	"factory/conveyor-long": Color(0.301, 0.301, 0.413),
	"factory/conveyor-long-stripe": Color(0.368, 0.368, 0.500),
	"factory/crane": Color(0.542, 0.496, 0.631),
	"factory/floor": Color(0.380, 0.380, 0.541),
	"factory/hopper-high-round": Color(0.376, 0.407, 0.611),
	"factory/hopper-high-square": Color(0.376, 0.407, 0.609),
	"factory/machine-fortified": Color(0.479, 0.458, 0.615),
	"factory/pipe-large-long": Color(0.339, 0.339, 0.462),
	"factory/piston-round": Color(0.454, 0.471, 0.657),
	"factory/robot-arm-b": Color(0.547, 0.504, 0.627),
	"factory/scanner-high": Color(0.597, 0.516, 0.622),
	"factory/screen-wide": Color(0.427, 0.427, 0.581),
	"factory/structure-doorway": Color(0.398, 0.398, 0.550),
	"factory/structure-wall": Color(0.518, 0.477, 0.597),
	"factory/structure-window": Color(0.521, 0.487, 0.599),
	"factory/top": Color(0.463, 0.463, 0.612),
	"factory/warning-orange": Color(0.621, 0.496, 0.608),
	"factory/warning-traffic": Color(0.559, 0.510, 0.627),
	"food/cup": Color(0.871, 0.871, 0.918),
	"food/cup-coffee": Color(0.833, 0.831, 0.872),
	"food/mug": Color(0.597, 0.426, 0.424),
	"food/pizza": Color(0.853, 0.573, 0.323),
	"food/pizza-box": Color(0.809, 0.809, 0.879),
	"food/soda-can": Color(0.790, 0.470, 0.498),
	"food/soda-can-crushed": Color(0.704, 0.509, 0.577),
	"furniture/bedSingle": Color(0.969, 0.832, 0.786),
	"furniture/bookcaseClosed": Color(0.953, 0.799, 0.660),
	"furniture/bookcaseClosedWide": Color(0.953, 0.799, 0.660),
	"furniture/bookcaseOpen": Color(0.953, 0.799, 0.660),
	"furniture/bookcaseOpenLow": Color(0.953, 0.799, 0.660),
	"furniture/books": Color(0.805, 0.718, 0.700),
	"furniture/cabinetBedDrawer": Color(0.953, 0.803, 0.669),
	"furniture/cardboardBoxClosed": Color(0.951, 0.797, 0.659),
	"furniture/cardboardBoxOpen": Color(0.951, 0.797, 0.659),
	"furniture/chairDesk": Color(0.871, 0.668, 0.656),
	"furniture/coatRackStanding": Color(0.953, 0.799, 0.660),
	"furniture/computerKeyboard": Color(0.599, 0.667, 0.667),
	"furniture/computerMouse": Color(0.589, 0.656, 0.656),
	"furniture/computerScreen": Color(0.696, 0.752, 0.755),
	"furniture/desk": Color(0.953, 0.799, 0.660),
	"furniture/floorFull": Color(0.953, 0.799, 0.660),
	"furniture/hoodModern": Color(0.676, 0.739, 0.739),
	"furniture/kitchenCabinet": Color(0.943, 0.814, 0.700),
	"furniture/kitchenCabinetDrawer": Color(0.944, 0.811, 0.694),
	"furniture/kitchenCabinetUpper": Color(0.951, 0.797, 0.659),
	"furniture/kitchenCoffeeMachine": Color(0.740, 0.795, 0.797),
	"furniture/kitchenFridge": Color(0.951, 0.974, 0.963),
	"furniture/kitchenMicrowave": Color(0.849, 0.882, 0.881),
	"furniture/kitchenSink": Color(0.936, 0.828, 0.733),
	"furniture/kitchenStove": Color(0.816, 0.778, 0.727),
	"furniture/lampRoundFloor": Color(0.958, 0.946, 0.842),
	"furniture/lampSquareFloor": Color(0.986, 0.956, 0.809),
	"furniture/lampSquareTable": Color(0.970, 0.950, 0.828),
	"furniture/laptop": Color(0.648, 0.709, 0.711),
	"furniture/loungeChair": Color(0.974, 0.646, 0.622),
	"furniture/loungeSofaLong": Color(0.974, 0.644, 0.621),
	"furniture/loungeSofaOttoman": Color(0.974, 0.650, 0.622),
	"furniture/pillow": Color(0.975, 0.640, 0.620),
	"furniture/pillowLong": Color(0.975, 0.640, 0.620),
	"furniture/plantSmall1": Color(0.862, 0.831, 0.694),
	"furniture/plantSmall2": Color(0.874, 0.827, 0.690),
	"furniture/plantSmall3": Color(0.867, 0.829, 0.692),
	"furniture/pottedPlant": Color(0.730, 0.864, 0.729),
	"furniture/radio": Color(0.879, 0.793, 0.708),
	"furniture/rugDoormat": Color(0.953, 0.799, 0.660),
	"furniture/rugRectangle": Color(0.965, 0.636, 0.617),
	"furniture/rugRound": Color(0.963, 0.636, 0.616),
	"furniture/rugSquare": Color(0.963, 0.636, 0.617),
	"furniture/sideTable": Color(0.961, 0.835, 0.728),
	"furniture/speaker": Color(0.889, 0.779, 0.674),
	"furniture/tableCoffee": Color(0.953, 0.799, 0.660),
	"furniture/tableCoffeeGlass": Color(0.868, 0.918, 0.914),
	"furniture/toaster": Color(0.815, 0.863, 0.869),
	"furniture/trashcan": Color(0.826, 0.871, 0.878),
	"furniture/wall": Color(0.842, 0.857, 0.853),
	"furniture/wallDoorway": Color(0.870, 0.849, 0.821),
	"furniture/wallWindow": Color(0.875, 0.851, 0.815),
	"graveyard/altar-stone": Color(0.604, 0.632, 0.759),
	"graveyard/candle": Color(0.899, 0.675, 0.525),
	"graveyard/column-large": Color(0.665, 0.621, 0.718),
	"graveyard/cross-wood": Color(0.653, 0.612, 0.710),
	"graveyard/crypt": Color(0.607, 0.635, 0.763),
	"graveyard/crypt-large": Color(0.526, 0.552, 0.669),
	"graveyard/crypt-small": Color(0.541, 0.568, 0.687),
	"graveyard/debris": Color(0.618, 0.646, 0.775),
	"graveyard/fire-basket": Color(0.246, 0.655, 0.476),
	"graveyard/grave": Color(0.805, 0.475, 0.332),
	"graveyard/gravestone-bevel": Color(0.600, 0.628, 0.755),
	"graveyard/gravestone-broken": Color(0.617, 0.645, 0.774),
	"graveyard/gravestone-cross": Color(0.606, 0.635, 0.762),
	"graveyard/gravestone-cross-large": Color(0.613, 0.641, 0.769),
	"graveyard/gravestone-decorative": Color(0.631, 0.661, 0.792),
	"graveyard/gravestone-round": Color(0.621, 0.650, 0.779),
	"graveyard/gravestone-wide": Color(0.590, 0.617, 0.743),
	"graveyard/iron-fence": Color(0.326, 0.655, 0.527),
	"graveyard/iron-fence-damaged": Color(0.330, 0.655, 0.530),
	"graveyard/lantern-candle": Color(0.410, 0.658, 0.504),
	"graveyard/lightpost-single": Color(0.426, 0.651, 0.523),
	"graveyard/pillar-obelisk": Color(0.609, 0.637, 0.765),
	"graveyard/pine": Color(0.397, 0.611, 0.450),
	"graveyard/rocks": Color(0.589, 0.616, 0.739),
	"graveyard/stone-wall": Color(0.554, 0.581, 0.701),
	"graveyard/stone-wall-column": Color(0.581, 0.609, 0.733),
	"graveyard/stone-wall-damaged": Color(0.545, 0.571, 0.691),
	"graveyard/urn-round": Color(0.447, 0.470, 0.576),
	"mini-arena/banner": Color(0.866, 0.550, 0.441),
	"mini-arena/floor": Color(0.863, 0.624, 0.471),
	"mini-dungeon/banner": Color(0.877, 0.397, 0.298),
	"mini-dungeon/barrel": Color(0.708, 0.563, 0.613),
	"mini-dungeon/chest": Color(0.672, 0.567, 0.632),
	"mini-dungeon/coin": Color(1.000, 0.679, 0.267),
	"mini-dungeon/column": Color(0.565, 0.588, 0.703),
	"mini-dungeon/floor": Color(0.490, 0.510, 0.612),
	"mini-dungeon/floor-detail": Color(0.499, 0.519, 0.623),
	"mini-dungeon/pot": Color(0.760, 0.468, 0.422),
	"mini-dungeon/rocks": Color(0.452, 0.461, 0.545),
	"mini-dungeon/stones": Color(0.446, 0.454, 0.537),
	"mini-dungeon/table": Color(0.717, 0.423, 0.310),
	"mini-forest/flag": Color(0.606, 0.448, 0.596),
	"mini-forest/patch-grass": Color(0.463, 0.737, 0.533),
	"mini-forest/plant": Color(0.444, 0.724, 0.534),
	"mini-forest/rocks-low": Color(0.469, 0.450, 0.579),
	"mini-forest/stones": Color(0.820, 0.488, 0.342),
	"mini-forest/tent": Color(0.570, 0.477, 0.695),
	"mini-forest/tree": Color(0.476, 0.678, 0.523),
	"mini-forest/tree-high": Color(0.511, 0.672, 0.516),
	"mini-market/cash-register": Color(0.480, 0.490, 0.577),
	"mini-market/column": Color(0.386, 0.464, 0.536),
	"mini-market/display-bread": Color(0.700, 0.530, 0.524),
	"mini-market/display-fruit": Color(0.872, 0.464, 0.328),
	"mini-market/floor": Color(0.873, 0.873, 0.919),
	"mini-market/freezer": Color(0.533, 0.553, 0.651),
	"mini-market/freezers-standing": Color(0.533, 0.552, 0.645),
	"mini-market/shelf-bags": Color(0.725, 0.660, 0.720),
	"mini-market/shelf-boxes": Color(0.686, 0.690, 0.781),
	"mini-market/shelf-end": Color(0.617, 0.633, 0.762),
	"mini-market/shopping-basket": Color(0.467, 0.702, 0.601),
	"mini-market/shopping-cart": Color(0.574, 0.576, 0.686),
	"mini-market/wall-window": Color(0.513, 0.528, 0.582),
	"modular-space/cables": Color(0.775, 0.589, 0.479),
	"nature/campfire_logs": Color(0.906, 0.698, 0.589),
	"nature/campfire_stones": Color(0.866, 0.948, 0.959),
	"nature/cliff_blockCave_rock": Color(0.899, 0.774, 0.661),
	"nature/cliff_blockHalf_rock": Color(0.859, 0.796, 0.692),
	"nature/cliff_block_rock": Color(0.890, 0.779, 0.669),
	"nature/cliff_large_rock": Color(0.948, 0.744, 0.619),
	"nature/ground_grass": Color(0.452, 0.930, 0.866),
	"nature/ground_pathTile": Color(0.698, 0.855, 0.773),
	"nature/log": Color(0.967, 0.848, 0.767),
	"nature/log_large": Color(0.962, 0.825, 0.736),
	"nature/log_stack": Color(0.950, 0.755, 0.635),
	"nature/plant_bushDetailed": Color(0.452, 0.930, 0.866),
	"nature/plant_bushLarge": Color(0.452, 0.930, 0.866),
	"nature/plant_bushSmall": Color(0.452, 0.930, 0.866),
	"nature/rock_largeA": Color(0.891, 0.779, 0.668),
	"nature/rock_largeC": Color(0.899, 0.774, 0.661),
	"nature/rock_largeD": Color(0.931, 0.827, 0.749),
	"nature/rock_tallC": Color(0.946, 0.800, 0.709),
	"nature/rock_tallJ": Color(0.937, 0.817, 0.734),
	"nature/stump_round": Color(0.952, 0.767, 0.653),
	"nature/tree_default": Color(0.577, 0.875, 0.804),
	"nature/tree_detailed": Color(0.604, 0.869, 0.797),
	"nature/tree_oak": Color(0.559, 0.879, 0.809),
	"nature/tree_pineRoundC": Color(0.520, 0.816, 0.819),
	"prototype/button-floor-round": Color(0.604, 0.563, 0.666),
	"prototype/column": Color(0.621, 0.650, 0.778),
	"prototype/crate": Color(0.655, 0.594, 0.629),
	"prototype/floor-square": Color(0.517, 0.538, 0.643),
	"prototype/floor-thick": Color(0.629, 0.658, 0.786),
	"prototype/wall-low": Color(0.623, 0.651, 0.780),
	"retro-urban/detail-barrier-type-a": Color(0.564, 0.592, 0.585),
	"retro-urban/pallet": Color(0.424, 0.361, 0.304),
	"retro-urban/road-asphalt-center": Color(0.239, 0.231, 0.225),
	"retro-urban/road-asphalt-damaged": Color(0.526, 0.515, 0.475),
	"retro-urban/road-asphalt-pavement": Color(0.549, 0.538, 0.496),
	"retro-urban/road-dirt-center": Color(0.520, 0.444, 0.369),
	"retro-urban/tree-park-pine-large": Color(0.358, 0.431, 0.336),
	"retro-urban/tree-pine-large": Color(0.278, 0.399, 0.279),
	"retro-urban/truck-grey-cargo": Color(0.401, 0.394, 0.393),
	"retro-urban/wall-a": Color(0.526, 0.491, 0.458),
	"retro-urban/wall-a-roof": Color(0.454, 0.440, 0.411),
	"retro-urban/wall-a-window": Color(0.529, 0.501, 0.474),
	"space-station/computer": Color(0.577, 0.566, 0.647),
	"space-station/computer-system": Color(0.548, 0.555, 0.652),
	"space-station/computer-wide": Color(0.606, 0.552, 0.588),
	"space-station/container": Color(0.870, 0.688, 0.569),
	"space-station/container-flat": Color(0.861, 0.689, 0.574),
	"space-station/container-tall": Color(0.855, 0.688, 0.593),
	"space-station/container-wide": Color(0.832, 0.684, 0.622),
	"space-station/display-wall": Color(0.573, 0.527, 0.568),
	"space-station/display-wall-wide": Color(0.594, 0.546, 0.588),
	"space-station/floor": Color(0.540, 0.567, 0.685),
	"space-station/floor-detail": Color(0.507, 0.532, 0.643),
	"space-station/floor-panel": Color(0.505, 0.531, 0.640),
	"space-station/pipe": Color(0.622, 0.651, 0.781),
	"space-station/skip": Color(0.714, 0.609, 0.591),
	"space-station/structure": Color(0.562, 0.588, 0.705),
	"space-station/table": Color(0.591, 0.577, 0.637),
	"space-station/table-display": Color(0.607, 0.585, 0.654),
	"space-station/table-display-planet": Color(0.501, 0.570, 0.727),
	"space-station/wall": Color(0.549, 0.575, 0.689),
	"space-station/wall-pillar": Color(0.571, 0.598, 0.717),
	"space-station/wall-window": Color(0.789, 0.649, 0.589),
	"tower-defense/detail-crystal": Color(0.789, 0.469, 0.923),
	"tower-defense/detail-crystal-large": Color(0.463, 0.609, 0.628),
	"tower-defense/detail-rocks": Color(0.587, 0.616, 0.736),
	"tower-defense/detail-rocks-large": Color(0.230, 0.641, 0.470),
}
const SWATCH_DEFAULT := Color(0.55, 0.55, 0.55)

## The largest multiplier `_tint_to` will hand a material, per channel, in sRGB.
## A near-black swatch (the 0.23 asphalt) legitimately wants > 1 to reach a
## mid-value hex; anything past this is a texture being asked to be something it
## is not, and clips to a flat colour instead of a material.
const TINT_MAX := 1.6

## LAW 6, as ONE number: the sRGB luminance the bare floor tile must display at.
## The window is 64-84 and 0.28 is 71/255 — middle of it, with the A/B variant
## and the walkway lift stacking to 1.1025 and still landing the brightest tile
## in the room at 83. Worked through the grade rather than guessed: albedo 0.28
## x moon (0.75 linear green, energy 1.9, NdotL 0.766) x exposure 0.88 comes out
## of the ACES fit at 0.278, i.e. the albedo it went in as. The floor's albedo
## IS its screen value under this rig, which is the fact the whole table below
## depends on.
##
## It is a LUMINANCE and not a colour because the LAW 6 hex table is a set of
## MATERIALS, not a set of values, and the values it happens to carry are not
## all legal: #4C3244 (Bazaar) is luminance 57 and #605028 (Vault) is 81. The
## floor keeps the hex's HUE and is normalised onto this value (`_floor_tone`).
const FLOOR_TARGET_L := 0.28

## The A/B tile pair, and the walkway/plaza lift over the field. LAW 6 caps a
## variant at 6% and per-tile jitter at 3%; two 5% steps stack to 1.10, which
## keeps the brightest tile in the room at ~80 and inside the window.
const FLOOR_VARIANT := 1.05
const FLOOR_WALK_LIFT := 1.05

## The seam under the floor, as a fraction of the floor tone. LAW 6 wants a
## 36-48 joint under a 64-84 tile. The ACES toe compresses a ratio hard down
## here — 0.68 of a 73 albedo displays at about 43, not 50 — so this is measured
## against the curve rather than against the albedo. It is always DARKER than
## the tile: the Corporate frame's "bright-blue lattice" was the space-station
## tile's own raised rim reading as a lit grid, and a bright seam is the one
## thing a floor may never have.
const FLOOR_SEAM_TONE := 0.68

## The two inset details, on roughly a tenth and a twentieth of the tiles (LAW
## 6: "one subtle inset detail on ~10% of tiles; nothing else on the floor").
## Both are a step DOWN from the tile — a recess, a plate joint — because on a
## floor the dark tone is the one that reads as structure and the light one
## reads as a mark somebody left.
const FLOOR_DETAIL_TONE := 0.88
const FLOOR_DETAIL_SIZE := 0.34
const FLOOR_GROOVE_TONE := 0.78
const FLOOR_GROOVE_SIZE := Vector2(0.62, 0.09)

## How far the out-of-bounds ground is lifted off the region BASE before it is
## painted. BASE itself renders at ~4/255 through the ACES toe, which is the
## "17-21% of the frame is black void" the critic measured; lifted it lands at
## ~17, which is the same value environment3d paints the BACKGROUND at — so the
## ground beyond the walls and the sky behind it are one continuous dark, and
## there is no hole in the frame at any yaw.
const VOID_LIFT := 0.06

## The value band a prop's albedo is COMPRESSED into once `place()` has
## desaturated it. Luminance, sRGB, and both ends are load-bearing:
##
##   * the floor is authored at 0.285 and displays at about the same, so a band
##     of 0.26-0.42 puts every prop's lit face between 68 and 102 on screen —
##     objects standing ON ground, never brighter than LAW 3's five bright
##     things and never darker than the ground they stand on;
##   * the LOW end is the answer to "bush and log meshes render as solid black
##     silhouettes with no lit face". The kit swatch is REMAPPED into the band
##     rather than clamped to it, so a white fridge is still lighter than a dark
##     crate — the relative reading survives, the absolute range does not.
const PROP_L_MIN := 0.26
const PROP_L_MAX := 0.42
## The swatch range the band is mapped from: darker than SW_LO or lighter than
## SW_HI and a model is simply at an end of the band.
const PROP_SW_LO := 0.20
const PROP_SW_HI := 0.95

## The one height ceiling this file names out loud, because two regions build a
## rack bank and they have to agree about how tall a server is.
const RACK_H := 1.8

## How far a desaturated prop leans off neutral grey toward the region's BASE
## hue. Enough that a room's props agree with its dark; not so far that they
## become a fourth colour.
const PROP_BASE_TILT := 0.35

## The region BASE normalised to a hue (max channel 1.0), set once per build and
## read by `_prop_tint`. Props keep their FORM and lose their colour, so the only
## saturated things left in a frame are the three LAW 2 hues on the surfaces
## allowed to carry them.
static var _base_hue := Color.WHITE

## The 2D wall colliders, in map px (region_builder.gd `_build_walls_themed`).
## These four numbers ARE the walkable rectangle, and the 3D border has to block
## exactly what the 2D border blocks or a post authored against one of them ends
## up inside masonry.
const WALL_N := 52.0
const WALL_S := 944.0
const WALL_W := 16.0
const WALL_E := 1274.0

## How far each border slab runs OUTWARD past the room, in map px. Purely a
## thickness for the collider — it changes nothing about where the player can
## stand, and everything about whether a dash can pass through a 16px wall.
const WALL_OUT := 128.0

## How far into the room the visible border ring's INNER FACE may reach, per
## side, in world units. North matches its 52px collider; west and east match
## their much thinner ones; the south is the wall NEAREST the 3/4 camera, so it
## is kept at the collider AND built low (RING_S_SCALE) rather than occluding
## the room the player is standing in. The bosses stage at y 906 — 0.6u north of
## the south collider — so a south wall that reached further would swallow five
## boss fights.
const RING_IN_N := 0.82
const RING_IN_S := 0.25
const RING_IN_W := 0.25
const RING_IN_E := 0.10
const RING_S_SCALE := 0.5

## Mesh parts of a Kenney model, memoised. Read-only derived data (the same
## shape as Map3D's own scene cache), so unlike the 2D builder's composition
## statics this one is safe to keep across a rebuild.
static var _parts_cache: Dictionary = {}
## Real measured bounds per model key (see _model_aabb). Same shape, same
## lifetime, same reason: derived read-only data, safe across a rebuild.
static var _aabb_cache: Dictionary = {}

## The 2D cover collider footprint, in map px (`_add_cover_body`). The 3D block
## uses the same rect so a fight is shaped identically in both renderers.
const COVER_PX := Vector2(76.0, 34.0)

## The two region one-shots RegionBuilder._add_interactables places from inline
## arguments rather than a table — the only positions in this file that are not
## read out of the 2D statics. Held ONCE, so the actor pass that instances them
## and the scatter keep-out that guards them can never disagree.
const SPECIAL_INTERACT := {
	"dependency_district": [["abandoned_package", Vector2(700, 620), "Recover package"]],
	"api_bazaar": [["backup_server", Vector2(760, 640), "Backup Server"]],
}

## Builds `region_id` under `root` and reports the arrival plaza and the room
## size in MAP PIXELS, exactly like RegionBuilder.build().
##
## Any id builds: an unknown one (Localhost included) falls through to the
## prototype kit rather than returning nothing, so a caller can never end up
## with a room that has no floor. `world3d.gd` still routes the apartment to
## LocalhostBuilder3D — this path exists so the contract has no hole in it, not
## because the apartment belongs here (3D_BIBLE §2.4).
static func build(root: Node3D, region_id: String) -> Dictionary:
	var w := float(RegionBuilder.REGION_SIZE.x * RegionBuilder.TILE_SIZE)
	var h := float(RegionBuilder.REGION_SIZE.y * RegionBuilder.TILE_SIZE)
	var spawn := Vector2(w * 0.5, h * 0.5)

	# Adopt this region's layout template before anything measures the floor:
	# _plaza_field / _band_y / _band_half all read RegionBuilder._layout, and a
	# stale one would paint the previous room's composition. This also refreshes
	# the portal keep-out boxes the scatter passes consult.
	RegionBuilder._use_layout(region_id)
	# ...and republish the cover list the 2D builder fills while it draws its
	# barriers, because RegionBuilder._token_spots() dodges it. Same rects, same
	# 34px inflation as _add_cover_body, so the eight token spots this file
	# instantiates are byte-identical to the 2D room's.
	RegionBuilder._cover_rects.clear()
	for cp: Vector2 in RegionBuilder._region_cover(region_id):
		RegionBuilder._cover_rects.append(
			Rect2(cp - COVER_PX * 0.5 - Vector2(34, 34), COVER_PX + Vector2(68, 68)))

	var theme := RegionBuilder._region_theme(region_id)
	var kit := _kit(region_id)
	var rng := RandomNumberGenerator.new()
	# Deterministic per region: walk back in and the room is the room.
	rng.seed = absi(region_id.hash()) + 1013

	# `glow` is the region's neon ACCENT and `accent` its WARM secondary — the
	# 2D theme table's key names, kept verbatim so the two files stay greppable.
	var accent: Color = theme.get("glow", Color("#24F0DC"))
	var warm: Color = theme.get("accent", Color("#FFB74A"))
	var focal: Vector2 = theme.get("focal", Vector2(w * 0.5, h * 0.35))

	# LAW 2's third colour is not a hue at all: it is the dark everything that is
	# not one of the three hues gets drawn through. Set BEFORE the first place().
	var base: Color = REGION_BASE.get(region_id, Color("#0E0C14"))
	_base_hue = _hue_of(base)

	var ctx := {
		"id": region_id,
		"base": base,
		"floor": _floor_tone(REGION_FLOOR.get(region_id, Color("#46464A"))),
		"root": root,
		"rng": rng,
		"w": w,
		"h": h,
		"spawn": spawn,
		"seed": RegionBuilder._region_seed(region_id),
		"kit": kit,
		"accent": accent,
		"warm": warm,
		"focal": focal,
		"lights": 0,
		"shadows": 0,
		"clear": _keep_clear(region_id, spawn),
	}

	var floors := _group(root, "Floor")
	var border := _group(root, "Border")
	var backdrop := _group(root, "Backdrop")
	var dress := _group(root, "Dressing")
	var cover := _group(root, "Cover")
	var lights := _group(root, "Lights")
	ctx["lightroot"] = lights

	_build_void(backdrop, ctx)
	_build_floor(floors, ctx)
	_build_border(border, ctx)
	_build_backdrop(backdrop, ctx)
	_build_patches(floors, ctx)
	_dress_region(dress, ctx)
	_build_cover(cover, ctx)
	_build_focal(dress, ctx)
	_build_signage(dress, ctx)
	_build_ambient_lights(ctx)
	_build_actors(root, ctx)

	return {"spawn": spawn, "size": Vector2(w, h)}

static func _group(parent: Node3D, n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	parent.add_child(g)
	return g

# --- colour helpers --------------------------------------------------------

## `c` scaled about black with alpha forced opaque. Colour arithmetic in
## GDScript carries alpha through the multiply, and an albedo_color with a > 1
## is a value nobody chose.
static func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)

## What model `key` reads at untouched (SWATCH), or the mid grey if unmeasured.
static func _swatch(key: String) -> Color:
	var c: Color = SWATCH.get(key, SWATCH_DEFAULT)
	return c

## The albedo multiplier that lands model `key` ON `target` (sRGB, times `lift`)
## once the GPU has multiplied it into the model's own texture. Divided in
## LINEAR space, because that is the space the multiply happens in: the engine
## converts albedo_color sRGB -> linear on upload and the texture is already
## linear by then, so lin(tint) * lin(swatch) == lin(target) exactly, on
## average, and the texture's local tones survive as ratios around it.
static func _tint_to(target: Color, key: String, lift: float = 1.0) -> Color:
	var sw := _swatch(key).srgb_to_linear()
	var want := _mul(target, lift).srgb_to_linear()
	var t := Color(want.r / maxf(sw.r, 0.002), want.g / maxf(sw.g, 0.002),
		want.b / maxf(sw.b, 0.002), 1.0).linear_to_srgb()
	return Color(minf(t.r, TINT_MAX), minf(t.g, TINT_MAX), minf(t.b, TINT_MAX), 1.0)

## sRGB relative luminance. The one number LAW 6 is written in.
static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## `c` normalised so its brightest channel is 1.0 — the colour's HUE with its
## value thrown away.
static func _hue_of(c: Color) -> Color:
	var m := maxf(maxf(c.r, c.g), maxf(c.b, 0.0001))
	return Color(c.r / m, c.g / m, c.b / m, 1.0)

## The LAW 6 hex, kept at its own hue and moved onto FLOOR_TARGET_L. The scale
## is bounded so a material can never be pushed more than a stop off the tone
## the bible named for it (Bazaar's #4C3244 wants +27%, the Vault's #605028
## wants -11%; nothing wants more than that).
static func _floor_tone(hex: Color) -> Color:
	var l := _lum(hex)
	if l <= 0.001:
		return hex
	var k := clampf(FLOOR_TARGET_L / l, 0.80, 1.35)
	return Color(minf(hex.r * k, 1.0), minf(hex.g * k, 1.0), minf(hex.b * k, 1.0), 1.0)

## The wall/masonry tone for a region: its BASE with a little of the ground
## lerped in, so the room's edge and its floor read as one place.
static func _wall_tone(base: Color, floor_c: Color) -> Color:
	return base.lerp(floor_c, 0.35)

## The albedo the backdrop BAND is drawn at: a step DARKER than the masonry in
## front of it, so nothing behind the room ever competes with the room. Worked
## through the grade: a Wildlands wall face lands at ~16-21/255 on screen and
## the band at ~10, against a void plane at ~16 — a treeline you can read the
## shape of, on ground you can see, which is what a horizon is. The old value (a
## flat 0.22 grey) came out BRIGHTER than the masonry, so the frames read as a
## lit second city standing in a black field.
static func _band_tone(base: Color, floor_c: Color) -> Color:
	return _mul(_wall_tone(base, floor_c), 0.80)

## `mesh` with every surface's material duplicated and multiplied by `tint`,
## for a MultiMesh — which has only a whole-instance `material_override` and no
## per-surface slot. Duplicating the ArrayMesh and setting each surface's
## material on the copy is the one way to tint a multi-surface tile (the
## graveyard path, the damaged asphalt, the cliffs, the retro-urban walls) and
## KEEP its surfaces: the previous fallback flattened them to one matte, which
## is LAW 6's structure thrown away at exactly the tiles that had the most.
## Surfaces that are not StandardMaterial3D get a matte at `fallback`. Returns
## null for a mesh that cannot be duplicated this way (a primitive), and the
## caller falls back to the override.
static func _tinted_mesh(mesh: Mesh, tint: Color, fallback: Color) -> Mesh:
	if not (mesh is ArrayMesh):
		return null
	var dup: ArrayMesh = (mesh as ArrayMesh).duplicate()
	for i in dup.get_surface_count():
		var src: Material = dup.surface_get_material(i)
		var m: StandardMaterial3D
		if src is StandardMaterial3D:
			m = (src as StandardMaterial3D).duplicate()
			m.albedo_color = m.albedo_color * tint
		else:
			m = Map3D.matte(fallback)
		dup.surface_set_material(i, m)
	return dup

## The albedo `place()` draws model `key` at, given what the caller asked for.
##
## THIS IS A DESATURATION, AND THE OLD ONE WAS NOT. A multiplier cannot take the
## colour out of a model — it scales every channel by the same ratio, so a
## saturated green lamp post multiplied by a grey is a darker saturated green
## lamp post, and the pass-3 critic named exactly that: green lamp posts in a
## gold graveyard, seven saturated hues in one Bazaar frame, seven red sofas in
## Production (they are `factory/box-large`, whose texture reads 0.83, 0.52,
## 0.37 — a fire engine).
##
## What happens instead: the model's own MEASURED reading (SWATCH) is reduced to
## a LUMINANCE, clamped into the band props are allowed to occupy, and re-hued —
## toward neutral grey leaned at the region's BASE when the caller asked for
## nothing, toward the caller's own colour when it did (a screen, a banner, a
## crystal). `_tint_to` then lands the model's mean on that target, and the
## texture's internal variation survives as ratios around it. Ten seconds of
## arithmetic per prop; no more rainbow.
static func _prop_target(key: String, want: Color) -> Color:
	var sw := _swatch(key)
	var t := clampf((_lum(sw) - PROP_SW_LO) / (PROP_SW_HI - PROP_SW_LO), 0.0, 1.0)
	var l := lerpf(PROP_L_MIN, PROP_L_MAX, t)
	if want == Color.WHITE:
		var grey := Color(l, l, l, 1.0)
		return grey.lerp(_mul(_base_hue, l), PROP_BASE_TILT)
	# A caller's colour is a HUE request, not a brightness one: it is placed at
	# the value the model would have had anyway, so "paint the banner in the
	# accent" can never also mean "make the banner the brightest thing here".
	var hue := _hue_of(want)
	var hl := maxf(_lum(hue), 0.05)
	return _mul(hue, clampf(l / hl, 0.0, 1.0))

# --- shared placement helpers ---------------------------------------------

## Instantiate Kenney model `key` ("pack/name") at map-px `px`, yawed `yaw`
## radians about world +Y, uniformly scaled by `s`, optionally tinted, and
## lifted to `y` world units. Returns null when the model is missing rather
## than crashing the region (Map3D.model is exists()-guarded).
##
## `y` means "where the BOTTOM of the model goes". Kenney origins are mostly
## floor-anchored, but not universally — space-station/table-display hangs
## 0.3u below its origin, the factory cogs and robot arms are pivoted on their
## axles, mini-dungeon/chest on its lid line — so anything with a negative
## min.y is lifted by its own overhang here rather than at forty call sites.
##
## EVERY model this file places is DESATURATED on the way in (LAW 7), against
## its own measured swatch — see `_prop_target` for why a multiplier could never
## do that and what the frames looked like while one was trying.
##
## `raw` skips it: for a tint that was already computed against the model's own
## swatch (`_tint_to`), a second pass would land it a stop under where it was
## aimed. The backdrop band, the corner posts and the two set-pieces parked
## outside the north wall use it; nothing inside the room does.
static func place(parent: Node3D, key: String, px: Vector2, yaw: float = 0.0,
		s: float = 1.0, tint: Color = Color.WHITE, y: float = 0.0,
		emission: float = 0.0, raw: bool = false) -> Node3D:
	var n := Map3D.model(key)
	if n == null:
		return null
	n.position = Map3D.to3d(px, y - _sink(key) * s)
	n.rotation = Vector3(0.0, yaw, 0.0)
	n.scale = Vector3(s, s, s)
	# A LIT surface is one of LAW 3's five bright things and is not desaturated:
	# its emission colour is the hue the fiction asked for, at the energy asked
	# for. Everything else is drawn at `_prop_target`.
	if emission > 0.0:
		Map3D.tint(n, tint, emission)
	elif raw:
		if tint != Color.WHITE:
			Map3D.tint(n, tint, 0.0)
	else:
		Map3D.tint(n, _tint_to(_prop_target(key, tint), key), 0.0)
	parent.add_child(n)
	return n

## Stop `node` and everything under it casting a shadow. The backdrop band uses
## it, and it is the single largest thing that was wrong with the frames: the
## sky ring stood 3-13 units tall at 1.85-3.2 room radii with shadows on, and
## the moon (pitch -50, yaw 30 — it comes from the south-east) threw that ring
## straight across the room. Wildlands measured 41/255 with p10 == p50 == p90:
## not a flat floor, a floor in one continuous cast shadow, with its bushes and
## logs reading as the "solid black silhouettes" the critic named.
static func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_no_shadow(c)

## Deterministic set dressing. Draws `count` props from `keys` inside the map-px
## `rect`, keeping out of the portal boxes, the solid cover, every authored
## anchor (see _keep_clear) and any zone not listed in `zones`
## (0 field / 1 walkway artery / 2 arrival plaza). Returns how many landed.
##
## `h_min`/`h_max` are HEIGHT CEILINGS IN WORLD UNITS, not scale factors — the
## player is 0.9u, and the pass-3 critic read the frames for exactly this
## ("office chairs a quarter of the player's height, laptops larger than the
## sofa"). See `_cap`: a prop is drawn at the size its kit authored unless that
## is over the ceiling. The remaining jitter is 12%, which is variety without
## being a second scale.
static func scatter(parent: Node3D, ctx: Dictionary, keys: Array, count: int,
		rect: Rect2, h_min: float = 0.45, h_max: float = 0.7,
		zones: Array = [0], y: float = 0.0, tint: Color = Color.WHITE) -> int:
	if keys.is_empty() or count <= 0:
		return 0
	var rng: RandomNumberGenerator = ctx["rng"]
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var seed_v: int = ctx["seed"]
	var clear: Array = ctx["clear"]
	var placed := 0
	for i in count:
		for attempt in 14:
			var p := Vector2(
				rng.randf_range(rect.position.x, rect.position.x + rect.size.x),
				rng.randf_range(rect.position.y, rect.position.y + rect.size.y))
			if not (_zone(p, w, h, seed_v) in zones):
				continue
			if RegionBuilder._in_portal(p) or RegionBuilder._in_cover(p):
				continue
			if not _free(p, clear):
				continue
			var key := str(keys[rng.randi() % keys.size()])
			# TWO rng draws, in the order the old pass drew them — a yaw and a
			# size. It matters: `_build_actors` stages the enemies off the SAME
			# generator after every dressing pass has run, so a scatter that
			# drew one extra number would move every enemy in the room. The
			# height ceiling is the band's midpoint and the 12% is the jitter.
			if place(parent, key, p, rng.randf_range(0.0, TAU),
					_cap(key, (h_min + h_max) * 0.5)
						* rng.randf_range(0.88, 1.0), tint, y) != null:
				placed += 1
			break
	return placed

## One OmniLight3D, budgeted and CLAMPED (LAW 3/4). Six a region, energy
## 0.5-1.2, range 6-10, attenuation 1.5, and every one of them motivated by
## something the player can see: a lamp, a monitor bank, a portal, a fire, a
## forge. There are no decorative lights in this file any more.
##
## `shadow` is only ever requested by a region's focal set-piece, so it doubles
## as that light's reserved slot: the room's one shadow caster can never be
## budgeted out by dressing that happens to be built first.
static func light(ctx: Dictionary, px: Vector2, color: Color, energy: float,
		reach: float, shadow: bool = false, y: float = 2.4) -> OmniLight3D:
	if int(ctx["lights"]) >= MAX_LIGHTS and not shadow:
		return null
	var parent: Node3D = ctx["lightroot"]
	var l := OmniLight3D.new()
	l.position = Map3D.to3d(px, y)
	l.light_color = color
	l.light_energy = clampf(energy, LIGHT_E_MIN, LIGHT_E_MAX)
	l.light_specular = 0.12
	l.omni_range = clampf(reach, LIGHT_R_MIN, LIGHT_R_MAX)
	l.omni_attenuation = LIGHT_ATTEN
	if shadow and int(ctx["shadows"]) < MAX_SHADOW_LIGHTS:
		l.shadow_enabled = true
		l.shadow_bias = 0.04
		l.shadow_normal_bias = 1.2
		l.shadow_blur = 1.4
		ctx["shadows"] = int(ctx["shadows"]) + 1
	parent.add_child(l)
	ctx["lights"] = int(ctx["lights"]) + 1
	return l

## An emissive slab. VISUAL_BIBLE_V2 LAW 3/7 leaves exactly three jobs for one:
## a SCREEN's lit face, the focal set-piece's ONE lit surface, and a fire. Not
## signage, not prop caps, not kerb strips, not a light box behind a crate —
## those were the frames' single biggest source of "no blacks anywhere", and the
## energy window here (2-3, not §7's old 4-7) is what keeps a screen a screen.
static func panel(parent: Node3D, px: Vector2, size: Vector3, color: Color,
		energy: float, yaw: float = 0.0, y: float = 1.6,
		e_max: float = PANEL_E_MAX) -> MeshInstance3D:
	energy = clampf(energy, PANEL_E_MIN, e_max)
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = Map3D.matte(color, energy)
	mi.position = Map3D.to3d(px, y)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## The region marquee is GONE, and so is the Label3D it was drawn with.
##
## Two rules retired it at once. VISUAL_BIBLE_V2 LAW 4 budgets four world labels
## a region and the HUD already spends one of them on the region's own name in
## its top strip, so a second copy of that name floating on the north wall was
## the same word twice; and world text in this project is now screen-space
## (scripts/world3d/screen_labels.gd) in the aliased UI font, which a
## distance-scaled billboard cannot be. Nothing in this file draws text.

## Drifting motes — dust, embers, spores. LAW 4 allows TWO emitters a region and
## caps the ambient layer at sixteen slow particles; the `amount` is clamped
## here because a 64-mote additive field is a haze pass by another name, and
## LAW 5 turns haze off. Non-additive on purpose: these are dust catching a
## light, not a light of their own.
static func motes(parent: Node3D, px: Vector2, color: Color, amount: int,
		extent: Vector3, rise: float, y: float = 1.2) -> GPUParticles3D:
	amount = clampi(amount, 1, 16)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 22.0
	pm.initial_velocity_min = rise * 0.4
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0.0, rise * 0.05, 0.0)
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.color = color
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(color.r, color.g, color.b, 0.25)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 5.0
	p.preprocess = 3.0
	p.explosiveness = 0.0
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(-extent - Vector3(1.0, 1.0, 1.0),
		(extent + Vector3(1.0, 6.0, 1.0)) * 2.0)
	p.position = Map3D.to3d(px, y)
	parent.add_child(p)
	return p

## A solid box in map-px space, on the walls layer. The ONLY thing in this file
## besides the border ring's four slabs that collides (see the file header).
static func _solid(parent: Node3D, px: Vector2, size_px: Vector2, height: float,
		y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Map3D.to3d(px, y)
	body.collision_layer = L_WALLS
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_px.x / PX, height, size_px.y / PX)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(cs)
	parent.add_child(body)
	return body

# --- MultiMesh plumbing ----------------------------------------------------

## Local transform of `node` relative to `root`, walked by hand rather than via
## global_transform: these models are built outside the SceneTree.
static func _rel_xform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func _collect_parts(node: Node, root: Node3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append({"mesh": mi.mesh, "xform": _rel_xform(mi, root)})
	for c in node.get_children():
		_collect_parts(c, root, out)

## The {mesh, xform} pairs inside "pack/name". Kenney GLBs import as a Node3D
## root with MeshInstance3D children, so a floor tile is normally one part and a
## wall segment one or two.
static func _parts(key: String) -> Array:
	if _parts_cache.has(key):
		return _parts_cache[key]
	var out: Array = []
	var inst := Map3D.model(key)
	if inst != null:
		_collect_parts(inst, inst, out)
		inst.free()
	_parts_cache[key] = out
	return out

## Draw `xforms` copies of model `key` as MultiMeshInstance3D(s) — one per mesh
## part. §7: floors and the border ring are hundreds of tiles and must never be
## hundreds of MeshInstance3Ds.
static func _mm(parent: Node3D, key: String, xforms: Array, tint: Color = Color.WHITE,
		shadows: bool = false) -> int:
	if xforms.is_empty():
		return 0
	var made := 0
	for part: Dictionary in _parts(key):
		var mesh: Mesh = part["mesh"]
		var pre: Transform3D = part["xform"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			mm.set_instance_transform(i, xf * pre)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Tint by DUPLICATING the mesh and multiplying each of its surface
		# materials (see _tinted_mesh), so the Kenney colormap texture survives
		# on every surface and the shared import is never mutated. A mesh that
		# cannot be duplicated that way gets a whole-instance override at the
		# tone the multiply would have produced against the model's swatch.
		if tint != Color.WHITE:
			var sw := _swatch(key)
			var flat := Color(tint.r * sw.r, tint.g * sw.g, tint.b * sw.b, 1.0)
			var tinted := _tinted_mesh(mesh, tint, flat)
			if tinted != null:
				mm.mesh = tinted
			else:
				mmi.material_override = Map3D.matte(flat)
		parent.add_child(mmi)
		made += 1
	return made

## Same, for a mesh built here rather than imported (floor decals, light strips).
static func _mm_mesh(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		mm.set_instance_transform(i, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

## A model's REAL bounds: its meshes' AABBs with every node transform applied,
## measured once and cached. NOT Map3D.bounds(), which is the raw glTF accessor
## box and ignores node scale — furniture/laptop is 0.16u tall, not the 0.37 the
## manifest claims; furniture/chairDesk is 0.61, not 0.42; mini-dungeon/chest is
## 0.45, not 0.30. A prop SIZED off those numbers is off by up to a half, which
## is the pass-3 defect ("chairs a quarter of the player's height"), and this is
## the number `_fit` divides by.
static func _model_aabb(key: String) -> AABB:
	if _aabb_cache.has(key):
		var cached: AABB = _aabb_cache[key]
		return cached
	var box := AABB()
	var first := true
	for part: Dictionary in _parts(key):
		var mesh: Mesh = part["mesh"]
		var xf: Transform3D = part["xform"]
		var b: AABB = xf * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		var m := Map3D.bounds(key)
		var mn: Array = m.get("min", [0.0, 0.0, 0.0])
		var sz: Array = m.get("size", [1.0, 1.0, 1.0])
		box = AABB(Vector3(float(mn[0]), float(mn[1]), float(mn[2])),
			Vector3(float(sz[0]), float(sz[1]), float(sz[2])))
	_aabb_cache[key] = box
	return box

## The uniform scale that makes `key` stand `h` world units tall — Map3D's
## `fit_height` arithmetic against the REAL bounds above.
##
## With one guard the naive version does not have: a FLAT, WIDE model (a cog is
## 1.00 x 0.22, a pallet 1.00 x 0.15) reaches a 0.9u height only by becoming
## four units across, and a four-unit cog is not a prop, it is a set-piece
## nobody asked for. The footprint is capped at `aspect` times the target
## height — 2.2 for a prop, which is the aspect a standing prop actually has,
## and tighter for the backdrop band, where a 2.4u-deep crypt would otherwise
## become eight units of horizon on its own.
static func _fit(key: String, h: float, aspect: float = 2.2) -> float:
	var b := _model_aabb(key)
	var s := h / maxf(b.size.y, 0.02)
	var foot := maxf(b.size.x, b.size.z)
	if foot > 0.01:
		s = minf(s, h * aspect / foot)
	return clampf(s, 0.05, 6.0)

## A model's authored height in world units, from the real bounds.
static func _height_of(key: String) -> float:
	return maxf(_model_aabb(key).size.y, 0.01)

## The scale a PROP is drawn at for a target height of `h`: its own, unless its
## own is bigger than `h`, in which case `h`.
##
## A CEILING and not a target, which is the whole lesson of pass 3. Every Kenney
## kit here is authored against the same 1 unit = 2 m as the 0.9u player — a
## desk really is 0.38u (77 cm), a chair 0.61u, a barrel 0.48u — so the props
## were never too SMALL; this file was multiplying them by 1.3 to 2.6 on the way
## in, and a 2.3-unit crate beside a 0.9-unit person is what the critic was
## reading when a laptop came out larger than a sofa. Fitting UP to a table of
## target heights would only have made a second, opposite mistake (a 0.75u desk
## is a metre and a half tall). So: authored size, capped.
##
## The caps this file spends, from the pass-3 brief: chair 0.9, sofa 0.8, desk
## 0.75, monitor 0.45, barrel 0.9, crate 0.6, shelf 1.6, tree 3.5, gravestone
## 0.8, crypt 1.8, lamp post 2.2, server rack 1.8. Only the focal set-pieces and
## the backdrop band are allowed past them, and they use `_fit` directly.
static func _cap(key: String, h: float) -> float:
	# NOT `minf(1.0, _fit(...))`: `_fit`'s footprint guard exists to stop a flat
	# model being blown UP to reach a height, and a cap never blows anything up.
	# Through the guard, `factory/conveyor-long` (2.00 x 0.40) capped at 0.45
	# came out at HALF size and the packing line grew gaps in it.
	return minf(1.0, h / maxf(_model_aabb(key).size.y, 0.02))

## `_fit` when the fiction wants a piece BIGGER than its kit authored it (a
## colonnade, a server rack, a set-piece), `_cap` otherwise. The one place a
## call site says out loud which of the two it means.
static func _size_for(key: String, h: float, grow: bool) -> float:
	return _fit(key, h) if grow else _cap(key, h)

## How far a model's geometry hangs BELOW its own origin (0 when it does not).
static func _sink(key: String) -> float:
	return minf(_model_aabb(key).position.y, 0.0)

## Where a border piece's ORIGIN must sit, measured inward from its side of the
## room in world units, so that its inner face lands exactly on `inner`. Read
## from the manifest because the kits put a wall's origin wherever they like: a
## factory structure is 2u deep from z -0.5, a graveyard fence 0.11u from -0.38.
static func _ring_offset(key: String, s: float, inner: float) -> float:
	return inner - _model_aabb(key).end.z * s

## Map-px distance from a model's origin to its +Z (camera-facing) face at
## scale `s`, plus a hair. An emissive slab meant to be a screen's PICTURE has
## to stand on the picture: a display-wall's origin is inside its cabinet, and
## a panel placed at the origin is sealed in the plastic and never blooms.
static func _front(key: String, s: float) -> float:
	return (_model_aabb(key).end.z * s + 0.03) * PX

## A model's authored width along its own X, in world units (1.0 if unknown,
## never below a quarter unit so a ring walk can always terminate).
static func _width(key: String) -> float:
	return maxf(_model_aabb(key).size.x, 0.25)

## Where a model's XZ footprint centre sits relative to its origin, in map px
## at scale `s`. Kenney origins are floor-anchored but not always centred
## (furniture/bookcaseClosed runs x 0..0.4 from a corner), and a cover block's
## crates have to sit INSIDE the 76x34 collider they dress.
static func _centre_px(key: String, s: float) -> Vector2:
	var b := _model_aabb(key)
	return Vector2(b.position.x + b.size.x * 0.5,
		b.position.z + b.size.z * 0.5) * s * PX

## The authored map-px anchor of a REGION_FLAVOR prop, or `fallback` when the
## region has no such prop. Interactable3D stands its own model on that anchor
## (3D_BIBLE §7), so a focal set-piece that shares its fiction builds AROUND it.
static func _flavor_pos(region_id: String, prop_id: String, fallback: Vector2) -> Vector2:
	for fe: Array in RegionBuilder.REGION_FLAVOR.get(region_id, []):
		if str(fe[0]) == prop_id:
			var fp: Vector2 = fe[1]
			return fp
	return fallback

# --- layout queries (all delegated to the 2D composition) ------------------

## 0 field, 1 walkway artery, 2 arrival plaza — the same three zones the 2D
## builder composes its rooms around, straight out of RegionBuilder's layout
## template. The 3D floor spends a different MATERIAL on each (the bible asks
## for two or three); the 2D floor spends none, because a pixel-art floor that
## changes value is a shape drawn on the ground. The tints below stay within
## ~12% for the same reason — the zoning is meant to be felt, not read.
static func _zone(p: Vector2, w: float, h: float, seed_v: int) -> int:
	if RegionBuilder._plaza_field(p, w, h, seed_v) < 0.0:
		return 2
	if absf(p.y - RegionBuilder._band_y(p.x, w, h, seed_v)) \
			< RegionBuilder._band_half(p.x, w, seed_v):
		return 1
	return 0

## Every authored anchor a prop must not stand on, as (x, y, radius) in map px.
## Assembled once per build and consulted by every scatter pass — this is what
## keeps a crate out of a boss arena, a portal arch, an NPC's stall or one of
## the eight composed token spots.
static func _keep_clear(region_id: String, spawn: Vector2) -> Array:
	var out: Array = []
	out.append(Vector3(spawn.x, spawn.y, 170.0))
	for pd: Dictionary in RegionBuilder._region_portals(region_id):
		var pp: Vector2 = pd.pos
		out.append(Vector3(pp.x, pp.y, 150.0))
	for nd: Dictionary in RegionBuilder._region_npcs(region_id):
		var np: Vector2 = nd.pos
		out.append(Vector3(np.x, np.y, 130.0))
	for ep: Vector2 in RegionBuilder._region_enemy_posts(region_id):
		out.append(Vector3(ep.x, ep.y, 120.0))
	for tp: Vector2 in RegionBuilder._token_spots(region_id, spawn):
		out.append(Vector3(tp.x, tp.y, 80.0))
	for fe: Array in RegionBuilder.REGION_FLAVOR.get(region_id, []):
		var fp: Vector2 = fe[1]
		out.append(Vector3(fp.x, fp.y, 110.0))
	for se: Array in SPECIAL_INTERACT.get(region_id, []):
		var sp: Vector2 = se[1]
		out.append(Vector3(sp.x, sp.y, 110.0))
	var arena := RegionBuilder._region_boss_arena(region_id)
	if arena != Vector2.ZERO:
		out.append(Vector3(arena.x, arena.y, 250.0))
	var theme := RegionBuilder._region_theme(region_id)
	var focal: Vector2 = theme.get("focal", Vector2.ZERO)
	if focal != Vector2.ZERO:
		out.append(Vector3(focal.x, focal.y, 150.0))
	return out

static func _free(p: Vector2, clear: Array) -> bool:
	for c: Vector3 in clear:
		if p.distance_to(Vector2(c.x, c.y)) < c.z:
			return false
	return true

# --- floor, void, border, backdrop ----------------------------------------

## Everything outside the room is ONE LIT GROUND PLANE in the region's BASE,
## lifted VOID_LIFT so it survives the ACES toe. It runs 95 units past every
## wall — far more than the 20 the brief asks for and further than the 3/4 rig
## can see at any yaw.
##
## THE LIFT IS THE WHOLE FIX. Painted at the raw BASE hex this plane rendered at
## about 4/255, and the critic measured the result: "17-21% of the frame is
## black void outside the map, with trees planted in it". environment3d paints
## the BACKGROUND at the same lifted value (its own VOID_LIFT), so ground and
## sky beyond the walls are now one continuous deep wall tone with no seam and
## no hole, and the border ring in front of it reads a clear step lighter.
##
## It also sits a hair BELOW the floor tiles, which is what makes the tile grid
## read: `_build_floor` insets each tile so the seam plane above this shows
## through as the joint between them (LAW 6, "visible joints").
static func _build_void(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var base: Color = ctx["base"]
	var pm := PlaneMesh.new()
	pm.size = Vector2(190.0, 190.0)
	var mi := MeshInstance3D.new()
	mi.name = "Void"
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base.lightened(VOID_LIFT)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mi.material_override = mat
	mi.position = Map3D.to3d(Vector2(w * 0.5, h * 0.5), -0.06)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## LAW 6, and the pass-3 rewrite of it.
##
## THE KIT TILES ARE GONE. Every measured failure in the pass-3 frames came from
## drawing the ground with somebody else's texture and hoping a multiplier would
## land it: Corporate at 21-29 with a BRIGHT blue lattice (that lattice is
## space-station/floor-panel's own raised rim, and LAW 6 says a seam is the DARK
## tone); the Bazaar at 27 in the dark half of mini-market/floor's checkerboard;
## Production wearing ~25 olive-khaki squares (retro-urban/road-asphalt-damaged,
## a patchy texture read as decals); Wildlands flat at 41. A texture whose
## internal range is 4:1 cannot be aimed at a 20-point window by scaling it.
##
## So the floor is GEOMETRY now, and every value in it is chosen:
##
##   VALUE. One tone per region, the LAW 6 hex re-hit onto FLOOR_TARGET_L
##   (`_floor_tone`), which under this grade displays within a few points of the
##   albedo — measured, not assumed: the regions whose swatch happened to be
##   right (Dependency, Cloud, Production) landed inside 3 points of their hex.
##
##   STRUCTURE. An A/B tile pair FLOOR_VARIANT apart, chosen per tile by the
##   same deterministic hash the 2D room uses, so the ground has grain without
##   having a pattern; the walkway artery and arrival plaza one further step up,
##   which is the room's wayfinding drawn in the floor; and one small inset
##   detail on about a tenth of the tiles. Nothing else. LAW 4 puts floor
##   overlays at zero and this obeys it.
##
##   SEAMS. Each tile is a 0.05u slab inset by FLOOR_SEAM about its own centre,
##   standing on a seam plane a step DARKER than the tile (FLOOR_SEAM_TONE). The
##   room shows ~14u across 1920px, so a 1.5% inset is a 2px joint with real
##   depth to it — a groove the moon shades, not a line painted on.
const FLOOR_SEAM := 0.985
const FLOOR_TILE_T := 0.05
const FLOOR_SEAM_Y := -0.02

static func _build_floor(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var seed_v: int = ctx["seed"]
	var floor_c: Color = ctx["floor"]

	# The joint the tiles show between them: room-sized, under the tile tops and
	# above the void plane, and always darker than the tile (LAW 6: 36-48).
	var seam_mesh := PlaneMesh.new()
	seam_mesh.size = Vector2(w / PX, h / PX)
	var seam := MeshInstance3D.new()
	seam.name = "Seams"
	seam.mesh = seam_mesh
	seam.material_override = Map3D.matte(_mul(floor_c, FLOOR_SEAM_TONE))
	seam.position = Map3D.to3d(Vector2(w * 0.5, h * 0.5), FLOOR_SEAM_Y)
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(seam)

	# Six buckets: three zones (field / artery / plaza) x the A/B pair. The zone
	# lift is the wayfinding; the A/B step is the grain.
	var tile := BoxMesh.new()
	tile.size = Vector3(1.0, FLOOR_TILE_T, 1.0)
	var buckets: Array = [[], [], [], [], [], []]
	var details: Array = []
	var grooves: Array = []
	var inset := Basis().scaled(Vector3(FLOOR_SEAM, 1.0, FLOOR_SEAM))
	for tz in RegionBuilder.REGION_SIZE.y:
		for tx in RegionBuilder.REGION_SIZE.x:
			var px := Vector2(float(tx) * PX + PX * 0.5, float(tz) * PX + PX * 0.5)
			var zi := _zone(px, w, h, seed_v)
			var hash_v := RegionBuilder._cell_hash(tx, tz)
			var bi := zi * 2 + int(hash_v % 2)
			var bucket: Array = buckets[bi]
			bucket.append(Transform3D(inset,
				Vector3(float(tx) + 0.5, -FLOOR_TILE_T * 0.5, float(tz) + 0.5)))
			# One inset detail on about a tenth of them, a plate joint on about a
			# twentieth. Two coprime moduli, so the two never land on one tile.
			if hash_v % 11 == 3:
				details.append(Transform3D(Basis(),
					Vector3(float(tx) + 0.5, 0.002, float(tz) + 0.5)))
			elif hash_v % 19 == 5:
				grooves.append(Transform3D(Basis(Vector3.UP, float(hash_v % 2) * PI * 0.5),
					Vector3(float(tx) + 0.5, 0.002, float(tz) + 0.5)))
	for bi2 in 6:
		var bucket2: Array = buckets[bi2]
		if bucket2.is_empty():
			continue
		var lift := 1.0 if bi2 < 2 else FLOOR_WALK_LIFT
		if bi2 % 2 == 1:
			lift *= FLOOR_VARIANT
		_mm_mesh(parent, tile, bucket2, Map3D.matte(_mul(floor_c, lift)))
	var det := PlaneMesh.new()
	det.size = Vector2(FLOOR_DETAIL_SIZE, FLOOR_DETAIL_SIZE)
	_mm_mesh(parent, det, details, Map3D.matte(_mul(floor_c, FLOOR_DETAIL_TONE)))
	var groove := PlaneMesh.new()
	groove.size = FLOOR_GROOVE_SIZE
	_mm_mesh(parent, groove, grooves, Map3D.matte(_mul(floor_c, FLOOR_GROOVE_TONE)))

## The room's edge: solid slabs matching the 2D wall rects exactly, plus the
## kit's own wall/fence/cliff pieces standing in the strip they block.
static func _build_border(parent: Node3D, ctx: Dictionary) -> void:
	var kit: Dictionary = ctx["kit"]
	var w: float = ctx["w"]
	var h: float = ctx["h"]

	# Four solids, one per side. The INNER faces land exactly on the 2D collider
	# spans, so the walkable rectangle is identical in both renderers; each slab
	# then runs WALL_OUT further outward and three units up, because the 2D west
	# wall is only 16px thick and 16px is a tunnel waiting for a dashing player.
	var mid_x := w * 0.5
	var mid_y := h * 0.5
	_solid(parent, Vector2(mid_x, (WALL_N - WALL_OUT) * 0.5),
		Vector2(w + 2.0 * WALL_OUT, WALL_N + WALL_OUT), 3.0)
	_solid(parent, Vector2(mid_x, (WALL_S + h + WALL_OUT) * 0.5),
		Vector2(w + 2.0 * WALL_OUT, h + WALL_OUT - WALL_S), 3.0)
	_solid(parent, Vector2((WALL_W - WALL_OUT) * 0.5, mid_y),
		Vector2(WALL_W + WALL_OUT, h + 2.0 * WALL_OUT), 3.0)
	_solid(parent, Vector2((WALL_E + w + WALL_OUT) * 0.5, mid_y),
		Vector2(w + WALL_OUT - WALL_E, h + 2.0 * WALL_OUT), 3.0)

	# The visible ring, grouped by key so the whole border is two or three
	# MultiMeshes rather than seventy nodes. A deterministic hash picks the
	# variant per piece, so the wall has rhythm without being noisy, and each
	# piece's inset is computed from its own bounds (see _ring_offset).
	#
	# Pieces are laid END TO END by their own scaled width, not one per tile: a
	# 1u wall segment at 1.3x on a 1u pitch overlaps its neighbour by a third,
	# and where a plain segment's face overlaps a window segment's face the two
	# are coplanar — a z-fighting seam every third piece, on every side.
	var keys: Array = kit["wall"]
	var s: float = kit.get("wall_s", 1.0)
	var s_south := s * RING_S_SCALE
	# LAW 2: the room's edge IS the BASE colour. Not a grey, not a lit surface —
	# the dark the three hues are read against. A hair of the floor tone is
	# lerped in so masonry and ground still look like they belong to one place,
	# and the cap below puts the single step of light back where it earns its
	# keep: the top edge, which is what tells a viewer where the room stops.
	var base: Color = ctx["base"]
	var floor_c: Color = ctx["floor"]
	var wall_tone := _wall_tone(base, floor_c)
	var by_key := {}
	for k: String in keys:
		by_key[k] = []
	var along := 0.0
	var i := 0
	while along < w:
		var kn := _ring_key(keys, i)
		var wd := _width(kn) * s * PX
		_ring_add(by_key, kn, Vector2(along + wd * 0.5, _ring_offset(kn, s, RING_IN_N) * PX),
			0.0, s)
		along += wd
		i += 1
	along = 0.0
	i = 7
	while along < w:
		var ks := _ring_key(keys, i)
		var wd := _width(ks) * s_south * PX
		_ring_add(by_key, ks,
			Vector2(along + wd * 0.5, h - _ring_offset(ks, s_south, RING_IN_S) * PX),
			PI, s_south)
		along += wd
		i += 1
	along = 0.0
	i = 3
	while along < h:
		var kw := _ring_key(keys, i)
		var wd := _width(kw) * s * PX
		_ring_add(by_key, kw, Vector2(_ring_offset(kw, s, RING_IN_W) * PX, along + wd * 0.5),
			PI * 0.5, s)
		along += wd
		i += 1
	along = 0.0
	i = 11
	while along < h:
		var ke := _ring_key(keys, i)
		var wd := _width(ke) * s * PX
		_ring_add(by_key, ke,
			Vector2(w - _ring_offset(ke, s, RING_IN_E) * PX, along + wd * 0.5),
			-PI * 0.5, s)
		along += wd
		i += 1
	for k: String in keys:
		_mm(parent, k, by_key[k], _tint_to(wall_tone, k), true)

	# The one step of light on the border: a thin cap along the top edge of each
	# side, on the ring's own inner face line. Four boxes. It is what stops a
	# BASE-dark wall from fusing into the BASE-dark void behind it, and it draws
	# the room's rectangle — which is half of "name the exits in one second",
	# because a doorway now reads as the gap in a line rather than as one dark
	# shape against another.
	#
	# Only where the ring is a BUILT edge. `_ring_key` mixes the kit's three wall
	# pieces per position, so a kit whose pieces disagree in height (the cliffs:
	# nature/cliff_blockHalf_rock is half the block beside it) has no single top
	# to cap — and a machined coping line along a rock face would be the wrong
	# fiction anyway. Measured, not assumed: masonry kits agree to the
	# millimetre, the graveyard's fences are 20% over its stone wall, and the
	# cliffs are 2:1.
	var lo := 99.0
	var hi := 0.0
	for k: String in keys:
		var kh := _height_of(k)
		lo = minf(lo, kh)
		hi = maxf(hi, kh)
	if hi > 0.0 and (hi - lo) <= hi * 0.1:
		var cap_h := hi * s
		var lip := base.lerp(floor_c, 0.62)
		_ring_cap(parent, Vector2(w * 0.5, RING_IN_N * PX), Vector2(w, 10.0), cap_h, lip)
		_ring_cap(parent, Vector2(w * 0.5, h - RING_IN_S * PX), Vector2(w, 10.0),
			cap_h * RING_S_SCALE, lip)
		_ring_cap(parent, Vector2(RING_IN_W * PX, h * 0.5), Vector2(10.0, h), cap_h, lip)
		_ring_cap(parent, Vector2(w - RING_IN_E * PX, h * 0.5), Vector2(10.0, h), cap_h, lip)

	# Corner posts, placed OUTSIDE the room so they can be tall without eating
	# any of the four corners the composition keeps clear.
	# Fitted to 3 units and SHADOWLESS. Corporate's post is a skyscraper: at
	# `s * 1.5` it stood 5.8 units tall a third of a unit off the room's corner,
	# with shadows on, which put a tower's shadow across the office floor — the
	# same defect as the old sky ring, four more times.
	var post: String = str(kit.get("wall_post", ""))
	if post != "":
		var idx := 0
		var post_tint := _tint_to(wall_tone, post)
		var post_s := _fit(post, 3.0)
		for corner: Vector2 in [Vector2(-20, -20), Vector2(w + 20, -20),
				Vector2(-20, h + 20), Vector2(w + 20, h + 20)]:
			var pn := place(parent, post, corner, float(idx) * PI * 0.5, post_s, post_tint,
				0.0, 0.0, true)
			if pn != null:
				_no_shadow(pn)
			idx += 1

## One length of border lip: a flat slab at the ring's top, a step lighter than
## the wall under it. Non-emissive on purpose (LAW 3 — an edge is not one of the
## five bright things); it reads because it is lighter than the wall, not
## because it glows.
static func _ring_cap(parent: Node3D, px: Vector2, size_px: Vector2, y: float,
		color: Color) -> void:
	if y <= 0.0:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(size_px.x / PX, 0.07, size_px.y / PX)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = Map3D.matte(color)
	# Centred 0.01 ABOVE the wall top, not on it: a cap whose top face is
	# coplanar with the masonry's top face z-fights it along its whole length.
	mi.position = Map3D.to3d(px, y - 0.025)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

static func _ring_key(keys: Array, salt: int) -> String:
	return str(keys[RegionBuilder._cell_hash(salt, 17) % keys.size()])

static func _ring_add(by_key: Dictionary, key: String, px: Vector2, yaw: float,
		s: float) -> void:
	var arr: Array = by_key[key]
	arr.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
		Map3D.to3d(px, 0.0)))

## THE BACKDROP BAND: one continuous low silhouette hugging the room, standing
## on the lit void, casting nothing.
##
## What this replaced, and why. The old pass scattered 32-46 pieces around an
## ellipse at 1.85-3.2 ROOM RADII at scales up to 5.6 — a Wildlands pine came
## out 7 units tall, thirty units from the wall, with shadows on. The critic saw
## the two consequences at once: "17-21% of the frame is black void outside the
## map with trees planted in it", and floors that measured flat and dark, which
## they were, because the moon (pitch -50, yaw 30 — it comes over the player's
## right shoulder from the south-east) was throwing that ring of giants straight
## across the room. Wildlands read 41/255 with p10 == p50 == p90: a room in one
## unbroken cast shadow.
##
## Three rules now, all of them measurable:
##   * POSITION. On a rectangular ring BAND_OUT units off the walls, walked by a
##     perimeter parameter so the pieces form a BAND rather than a field. The
##     void is empty apart from this.
##   * SIZE. Fitted by HEIGHT (BAND_H), not by a kit scale factor, so a pine and
##     a skyscraper agree about where the horizon is.
##   * VALUE and SHADOW. `_band_tone` — a step darker than the masonry in front
##     of it — and no shadow casting at all. A backdrop is a silhouette; it is
##     not a light rig and it is not allowed to be one.
const BAND_OUT_MIN := 5.0
const BAND_OUT_MAX := 11.0
const BAND_H_MIN := 2.4
const BAND_H_MAX := 4.6
const BAND_ASPECT := 1.3
## The camera sits about 3.6 units beyond the SOUTH wall at this pitch, so the
## south arc of the ring is the one arc that could ever stand between the lens
## and the room. It is pushed six units further out than the rest — behind the
## rig at every yaw, and the ring stays closed for the two corners that are not.
const BAND_OUT_SOUTH := 6.0

static func _build_backdrop(parent: Node3D, ctx: Dictionary) -> void:
	var kit: Dictionary = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var keys: Array = kit.get("sky", [])
	if keys.is_empty():
		return
	var count: int = int(kit.get("sky_n", 34))
	var base: Color = ctx["base"]
	var floor_c: Color = ctx["floor"]
	var band := _band_tone(base, floor_c)
	var per := 2.0 * (w + h)
	for i in count:
		var t := (float(i) + rng.randf_range(0.15, 0.85)) / float(count)
		var d := t * per
		var out := rng.randf_range(BAND_OUT_MIN, BAND_OUT_MAX) * PX
		var p := Vector2.ZERO
		if d < w:
			p = Vector2(d, -out)
		elif d < w + h:
			p = Vector2(w + out, d - w)
		elif d < 2.0 * w + h:
			p = Vector2(2.0 * w + h - d, h + out + BAND_OUT_SOUTH * PX)
		else:
			p = Vector2(-out, per - d)
		var key := str(keys[rng.randi() % keys.size()])
		var n := place(parent, key, p, rng.randf_range(0.0, TAU),
			_fit(key, rng.randf_range(BAND_H_MIN, BAND_H_MAX), BAND_ASPECT),
			_tint_to(band, key), 0.0, 0.0, true)
		if n != null:
			_no_shadow(n)

## The swept pad in the boss arena — the 3D reading of the 2D `_arena` mark, and
## the region's ONE floor decal.
##
## These were BLEND_MODE_MUL, and that is where the black holes in the QA frames
## came from: the framebuffer is LINEAR (HANDOVER §4.11), so a 0.46 sRGB colour
## multiplies the floor by ~0.18 and every enemy post got a near-black ellipse
## painted under it. A wall-AO strip is capped at 26% by LAW 6; this is the same
## idea, so it is now a plain alpha wash at 18% of a dark tone — a shadow you
## would have to look for, which is all a scuff mark should ever be.
static func _build_patches(parent: Node3D, ctx: Dictionary) -> void:
	var region_id: String = ctx["id"]
	var base: Color = ctx["base"]
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 20
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_color = Color(base.r, base.g, base.b, 0.18)
	# ONE decal a region. LAW 4 puts floor overlays at zero and LAW 6 allows at
	# most three decals; the scuff under every enemy post was six to ten of them,
	# which is a floor with marks all over it — the "wear field / blotches /
	# drag marks" the bible lists by name as a signature of slop. The boss arena
	# keeps its swept pad, because that one is a place, not a texture.
	var xf: Array = []
	var arena := RegionBuilder._region_boss_arena(region_id)
	if arena != Vector2.ZERO:
		var w: float = ctx["w"]
		var h: float = ctx["h"]
		# Clamped inward on the same rule the 2D `_arena` uses, so a boss post
		# near a wall does not get its floor painted into the masonry.
		var a := Vector2(clampf(arena.x, 260.0, w - 260.0),
			clampf(arena.y, 250.0, h - 94.0))
		xf.append(Transform3D(Basis().scaled(Vector3(2.7, 1.0, 2.7)), Map3D.to3d(a, 0.012)))
	_mm_mesh(parent, disc, xf, mat)

# --- cover, focal, signage, ambient ---------------------------------------

## The solid barriers a fight is shaped around. Cargo, not lanterns: the lit cap
## each of these used to carry (an emissive chip per block, six to eight a room)
## was props glowing, which LAW 3 forbids outright. A barrier now reads as a
## barrier because it is a SILHOUETTE standing on lit ground, which is how cover
## reads in every game the bible names.
static func _build_cover(parent: Node3D, ctx: Dictionary) -> void:
	var region_id: String = ctx["id"]
	var kit: Dictionary = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var key := str(kit.get("cover", "prototype/crate"))
	# A barrier is CARGO at cargo size (LAW: `_cap`). The kit tables used to name
	# a scale here and every one of them was over 1.0, which is how Production
	# ended up with what the critic counted as "seven red sofas": twenty-one
	# `factory/box-large` at 1.0-1.35, i.e. 1.1u-wide fire-engine-orange blocks.
	# They are 0.6u crates in the region's own dark now.
	var s := _cap(key, float(kit.get("cover_h", 0.6)))
	var top := _height_of(key) * s
	# Kenney origins are not always footprint-centred (a bookcase grows from
	# its corner); subtracting the model's own centre keeps the pair inside
	# the 76x34 collider instead of hanging a crate's width off one end.
	var off := _centre_px(key, s)
	var idx := 0
	for cp: Vector2 in RegionBuilder._region_cover(region_id):
		_solid(parent, cp, COVER_PX, 1.15)
		# Two pieces side by side inside the collider's own 76x34 footprint and
		# one stacked on top, so a barrier reads as cargo somebody left there
		# rather than as an extruded box.
		place(parent, key, cp + Vector2(-24, 0) - off, rng.randf_range(-0.35, 0.35), s)
		place(parent, key, cp + Vector2(24, 3) - off * 0.92, rng.randf_range(-0.35, 0.35),
			s * 0.92)
		if idx % 2 == 0:
			place(parent, key, cp + Vector2(2, -5) - off * 0.75, rng.randf_range(-0.35, 0.35),
				s * 0.75, Color.WHITE, top)
		idx += 1

## The region's ONE brightest thing: its landmark, at the authored focal, under
## the only shadow-casting OmniLight in the room.
static func _build_focal(parent: Node3D, ctx: Dictionary) -> void:
	match str(ctx["id"]):
		"dependency_district": _focal_dependency(parent, ctx)
		"stackoverflow_ruins": _focal_ruins(parent, ctx)
		"api_bazaar": _focal_bazaar(parent, ctx)
		"cloud_district": _focal_cloud(parent, ctx)
		"open_source_wildlands": _focal_wildlands(parent, ctx)
		"corporate_enterprise": _focal_corporate(parent, ctx)
		"gpu_mines": _focal_mines(parent, ctx)
		"production": _focal_production(parent, ctx)
		"token_vault": _focal_vault(parent, ctx)

## The room's ONE monitor bank, and the kerb of the walkway.
##
## This used to be five emissive slabs strung across the north wall with a light
## under each — signage that glowed, which LAW 3 names twice ("signs do not
## glow") and which by itself put five bright sources in every frame. It is now
## a single bank of three small screens at one place on that wall, sharing one
## motivated light: a thing in the room that is switched on, in the region's
## ACCENT, near enough to the doorway line to help the player read the wall.
##
## The artery's edge strips were emissive too — the bright band running corner
## to corner through the Dependency District frame is exactly them. A road is
## not a light. They are a LIGHTER FLOOR TONE now (LAW 6's walkway variant, one
## step up again), which reads as a kerb at the value the ground is drawn at.
static func _build_signage(parent: Node3D, ctx: Dictionary) -> void:
	var kit: Dictionary = ctx["kit"]
	var accent: Color = ctx["accent"]
	var floor_c: Color = ctx["floor"]
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var seed_v: int = ctx["seed"]

	# y 60, not 46: the north ring's inner face is at RING_IN_N (52px), so a
	# panel north of that is inside the masonry and never seen. 60 puts the
	# slab's back face 0.08u proud of the wall. The bank sits west of centre so
	# it does not stack with the region title or with the marquee below it.
	#
	# Screens are MOUNTED, and the old rig hung them at a fixed y 1.5-2.3 on
	# walls that are 0.73u tall in the Ruins and 3.0u in the Depot — half the
	# regions had their signage floating in the void above the wall it was
	# supposed to be screwed to. The bank is sized and hung off the kit's own
	# wall height, and the regions whose "wall" is a cliff or a graveyard fence
	# do not get one at all, because a monitor bank bolted to a rock face is a
	# bright thing with no fiction behind it (LAW 3: motivated, or not at all).
	var wall_h := _height_of(str((kit["wall"] as Array)[0])) \
		* float(kit.get("wall_s", 1.0))
	# SIGN_E_MAX, not a screen's: at 2.4 this bank was the "blown pink-white neon
	# slab at the top edge" the critic found the region title drawn over, in the
	# Bazaar and in Production. A sign is legible, not incandescent.
	if bool(kit.get("bank", true)):
		var ph := clampf(wall_h * 0.45, 0.28, 0.6)
		var bank_y := maxf(wall_h - ph * 0.5 - 0.12, ph * 0.5 + 0.05)
		var bank_x := w * 0.5 - 250.0
		for i in 3:
			panel(parent, Vector2(bank_x + float(i) * 78.0, 60.0),
				Vector3(1.05, ph, 0.07), accent, SIGN_E_MAX, 0.0, bank_y, SIGN_E_MAX)
		light(ctx, Vector2(bank_x + 78.0, 96.0), accent, 0.9, 8.0, false,
			minf(bank_y, 2.4))

	# The kerb: one MultiMesh, forty short segments, no emission at all, and 12%
	# over the floor tone — LAW 6's highlight band starts at 96, and a strip
	# drawn there is the corner-to-corner diagonal again with the glow taken
	# off. At 1.12 it displays around 80: a kerb you find, not a line you read.
	var strip := BoxMesh.new()
	strip.size = Vector3(0.85, 0.02, 0.09)
	var xf: Array = []
	for i in 20:
		var x := 120.0 + float(i) * (w - 240.0) / 19.0
		var cy := RegionBuilder._band_y(x, w, h, seed_v)
		var half := RegionBuilder._band_half(x, w, seed_v)
		for k: float in [1.0, -1.0]:
			xf.append(Transform3D(Basis(), Map3D.to3d(Vector2(x, cy + k * half), 0.015)))
	_mm_mesh(parent, strip, xf, Map3D.matte(_mul(floor_c, 1.12)))

	# No caption. The HUD already carries the region's name in its top strip and
	# LAW 4 budgets four world labels a region, so a billboard repeating it on
	# the north wall was the same word twice — see the note where `marquee` used
	# to be. `wall_h` is still read above; nothing else in this file draws text.

## The last light in the rig: ONE warm fill on the person you are meant to talk
## to. That is the whole of it.
##
## What used to be here: a lamp beside every door (two a region), a fill on
## every NPC, and one on every flavour prop — eight or nine lights that existed
## because a thing was there, not because anything in the fiction was switched
## on. The doors light themselves (Portal3D lights its own gate in the
## destination's hue, and two sources on one arch is a blob), and the flavour
## props are exactly the "generic props" LAW 3 says may not be lit; the 2D twin
## reached the same conclusion in its round-11 notes — "a region has one light
## and it is the set-piece lamp".
static func _build_ambient_lights(ctx: Dictionary) -> void:
	var region_id: String = ctx["id"]
	var warm: Color = ctx["warm"]
	var npcs := RegionBuilder._region_npcs(region_id)
	if npcs.is_empty():
		return
	var nd: Dictionary = npcs[0]
	var na: Vector2 = nd.pos
	var np := RegionBuilder._npc_spot(na)
	light(ctx, np + Vector2(0, -40), warm, 0.85, 6.5, false, 2.4)

# --- actors ----------------------------------------------------------------

static func _scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

## Enemies, NPCs, portals, tokens and interactables — every one of them at a
## position this file reads rather than chooses, in the order and with the
## exports RegionBuilder._populate_region uses. The counts in _region_enemies
## are FROZEN; the post table is consumed in the same order so a boss lands in
## its arena.
static func _build_actors(root: Node3D, ctx: Dictionary) -> void:
	var region_id: String = ctx["id"]
	var spawn: Vector2 = ctx["spawn"]
	var rng: RandomNumberGenerator = ctx["rng"]

	var props := _group(root, "Props")
	var enemies := _group(root, "Enemies")
	var tokens := _group(root, "Tokens")
	var npcs := _group(root, "NPCs")
	var portals := _group(root, "Portals")

	# Tokens: the eight composed spots and the region's own type rotation.
	var token_scene := _scene(SCENE_TOKEN)
	if token_scene != null:
		var types := RegionBuilder._region_token_types(region_id)
		var spots := RegionBuilder._token_spots(region_id, spawn)
		for i in spots.size():
			var t := token_scene.instantiate()
			t.token_type = str(types[i % types.size()])
			(t as Node3D).position = Map3D.to3d(spots[i], 0.55)
			tokens.add_child(t)

	# Enemies: types and counts unchanged, posts consumed in table order.
	var enemy_scene := _scene(SCENE_ENEMY)
	if enemy_scene != null:
		var posts := RegionBuilder._region_enemy_posts(region_id)
		var post_i := 0
		for e: Dictionary in RegionBuilder._region_enemies(region_id):
			var count: int = int(e.get("count", 2))
			for i in count:
				var want := Vector2.ZERO
				if post_i < posts.size():
					var wp: Vector2 = posts[post_i]
					want = wp
					post_i += 1
				var at := RegionBuilder._staged(want, spawn, rng)
				var en := enemy_scene.instantiate()
				en.enemy_type = str(e.get("type", "bug"))
				en.max_hp = int(e.get("hp", 30))
				en.is_boss = bool(e.get("boss", false))
				(en as Node3D).position = Map3D.to3d(at)
				enemies.add_child(en)

	var npc_scene := _scene(SCENE_NPC)
	if npc_scene != null:
		for nd: Dictionary in RegionBuilder._region_npcs(region_id):
			var n := npc_scene.instantiate()
			n.npc_id = str(nd.id)
			var qids: Array[String] = []
			for q in nd.get("quests", []):
				qids.append(str(q))
			n.quest_ids = qids
			var na: Vector2 = nd.pos
			(n as Node3D).position = Map3D.to3d(RegionBuilder._npc_spot(na))
			npcs.add_child(n)

	var portal_scene := _scene(SCENE_PORTAL)
	if portal_scene != null:
		for pd: Dictionary in RegionBuilder._region_portals(region_id):
			if not (GameManager.is_region_unlocked(pd.to) or pd.get("always_open", false)):
				continue
			var p := portal_scene.instantiate()
			p.target_region = str(pd.to)
			p.portal_label = str(pd.get("label", pd.to))
			var pa: Vector2 = pd.pos
			(p as Node3D).position = Map3D.to3d(pa)
			portals.add_child(p)

	# Interactables. Mirrors RegionBuilder._add_interactables: the two
	# region-specific one-shots (SPECIAL_INTERACT — the only two positions in
	# this file that are not read from a table, because over there they are
	# inline arguments), then the REGION_FLAVOR props with one_shot false.
	# Interactable3D owns the per-interact_id model (3D_BIBLE §7), so this
	# places no art of its own, and no light either: a flavour prop is exactly
	# the "generic prop" LAW 3 forbids lighting. The focal set-pieces are
	# composed AROUND these anchors and the focal lamp is what finds them.
	var interact_scene := _scene(SCENE_INTERACT)
	if interact_scene != null:
		for se: Array in SPECIAL_INTERACT.get(region_id, []):
			var sp: Vector2 = se[1]
			_add_prop(props, interact_scene, str(se[0]), sp, str(se[2]), true)
		for entry: Array in RegionBuilder.REGION_FLAVOR.get(region_id, []):
			var ep: Vector2 = entry[1]
			_add_prop(props, interact_scene, str(entry[0]), ep, str(entry[2]), false)

static func _add_prop(parent: Node3D, scene: PackedScene, id: String, px: Vector2,
		text: String, one_shot: bool) -> Node:
	var node := scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.one_shot = one_shot
	(node as Node3D).position = Map3D.to3d(px)
	parent.add_child(node)
	return node

# --- per-region kits (3D_BIBLE §7 region -> kit) ---------------------------

## Border ring, backdrop family and cover model per region. Everything here is a
## LOOK; not one position lives in this table.
##
## THERE IS NO FLOOR KEY. The ground is generated (see `_build_floor`) from the
## region's LAW 6 tone, because every kit tile this table used to name carried
## its own 4:1 internal range and no multiplier could aim that at LAW 6's
## twenty-point window.
##
## No COLOURS live here any more either. Every tint this file spends is derived
## from the two LAW tables at the top of the file — REGION_BASE for the dark and
## REGION_FLOOR for the ground — so a region cannot drift out of its own three
## hues by somebody editing one row of a kit. What is left is a choice of
## MATERIAL: which tile, which wall, which silhouette stands on the horizon.
##
## One hard constraint on the values below, learned from the models: every
## "wall" key is 1.0 units wide in X, so the ring tiles at 1-unit pitch with
## neither gaps nor coplanar overlap. Depth is free — the ring computes each
## piece's inset from its own bounds.
static func _kit(region_id: String) -> Dictionary:
	match region_id:
		"dependency_district":
			# A depot that has been shipping node_modules since 2016.
			return {
				"wall": ["factory/structure-wall", "factory/structure-window",
					"factory/structure-doorway"],
				"wall_s": 1.0,
				"wall_post": "city-industrial/chimney-large",
				"sky": ["city-industrial/building-a", "city-industrial/building-h",
					"city-industrial/building-m", "city-industrial/chimney-large",
					"city-industrial/building-q"],
				"sky_n": 36,
				"cover": "prototype/crate", "cover_h": 0.6,
			}
		"stackoverflow_ruins":
			# A graveyard of dead answers, lit by the one that got accepted.
			return {
				# STONE ONLY. `graveyard/iron-fence` reads (0.33, 0.65, 0.53) —
				# a green railing with MAGENTA finials on it, and the ring
				# walked it round all four walls: that is the row of pink
				# spikes along the north and west edges of the pass-3 frame,
				# and magenta is the Bazaar's ACCENT, not this room's. The
				# three stone pieces are 1.00u wide apiece, which is what
				# the ring's end-to-end walk needs.
				"wall": ["graveyard/stone-wall", "graveyard/stone-wall-damaged",
					"graveyard/stone-wall-column"],
				"wall_s": 1.15, "bank": false,
				"wall_post": "graveyard/pillar-obelisk",
				"sky": ["graveyard/pine", "graveyard/crypt-large", "graveyard/pillar-obelisk",
					"retro-urban/tree-pine-large", "graveyard/column-large"],
				"sky_n": 40,
				"cover": "graveyard/gravestone-wide", "cover_h": 0.8,
			}
		"api_bazaar":
			# Night market. Awnings, registers, and somebody selling you calls.
			return {
				"wall": ["retro-urban/wall-a", "retro-urban/wall-a-window",
					"mini-market/wall-window"],
				"wall_s": 1.25,
				"wall_post": "mini-market/column",
				"sky": ["city-commercial/building-a", "city-commercial/building-f",
					"city-commercial/building-k", "city-commercial/low-detail-building-a",
					"retro-urban/wall-a-roof"],
				"sky_n": 34,
				"cover": "mini-market/shelf-boxes", "cover_h": 0.85,
			}
		"cloud_district":
			# Somebody else's computer, with a very good view.
			return {
				"wall": ["space-station/wall", "space-station/wall-window",
					"space-station/wall-pillar"],
				"wall_s": 1.3,
				"wall_post": "space-station/wall-pillar",
				"sky": ["space-station/container-tall", "space-station/structure",
					"city-commercial/building-skyscraper-a",
					"city-commercial/building-skyscraper-d", "space-station/skip"],
				"sky_n": 32,
				"cover": "space-station/container", "cover_h": 0.6,
			}
		"open_source_wildlands":
			# A forest of forks. One person has been maintaining it for nine years.
			return {
				"wall": ["nature/cliff_block_rock", "nature/cliff_blockHalf_rock",
					"nature/cliff_blockCave_rock"],
				"wall_s": 1.1, "bank": false,
				"wall_post": "nature/rock_tallC",
				"sky": ["nature/tree_default", "nature/tree_pineRoundC", "mini-forest/tree-high",
					"retro-urban/tree-park-pine-large", "nature/tree_detailed"],
				"sky_n": 44,
				"cover": "mini-forest/rocks-low", "cover_h": 0.55,
			}
		"corporate_enterprise":
			# Open plan, glass everywhere, one all-hands you cannot leave.
			return {
				"wall": ["space-station/wall-window", "space-station/wall",
					"space-station/wall-pillar"],
				"wall_s": 1.35,
				"wall_post": "city-commercial/building-skyscraper-a",
				"sky": ["city-commercial/building-skyscraper-a",
					"city-commercial/building-skyscraper-b",
					"city-commercial/building-skyscraper-c",
					"city-commercial/building-skyscraper-e",
					"city-commercial/low-detail-building-wide-a"],
				"sky_n": 32,
				"cover": "furniture/bookcaseClosed", "cover_h": 0.9,
			}
		"gpu_mines":
			# A cavern full of rented heat. Its dressing is deliberately NOT the
			# Cloud's (`space-station/container-tall`) nor the two factories'
			# (`factory/pipe-large-long` down the west wall): the critic found
			# regions sharing a set-piece, and a mine dressed like a data centre
			# is one of the ways that happens.
			return {
				"wall": ["nature/cliff_block_rock", "nature/cliff_blockCave_rock",
					"nature/cliff_large_rock"],
				"wall_s": 1.15, "bank": false,
				"wall_post": "nature/rock_tallJ",
				"sky": ["nature/cliff_large_rock", "nature/cliff_block_rock",
					"nature/rock_tallJ", "nature/rock_largeD", "graveyard/rocks"],
				"sky_n": 46,
				"cover": "mini-dungeon/rocks", "cover_h": 0.5,
			}
		"production":
			# The line is running. It is 03:00 and the line is running.
			return {
				"wall": ["factory/structure-wall", "factory/structure-window",
					"factory/structure-doorway"],
				"wall_s": 1.0,
				"wall_post": "city-industrial/chimney-large",
				"sky": ["city-industrial/building-c", "city-industrial/building-j",
					"city-industrial/chimney-large", "city-industrial/chimney-medium",
					"city-industrial/building-t"],
				"sky_n": 36,
				"cover": "factory/box-large", "cover_h": 0.6,
			}
		"token_vault":
			# Gold, violet, and a door that should not be open.
			return {
				"wall": ["castle/wall", "castle/wall-half", "castle/wall-pillar"],
				"wall_s": 1.05,
				"wall_post": "castle/tower-square-base",
				"sky": ["castle/tower-square-base", "castle/tower-square-mid",
					"castle/tower-hexagon-base", "castle/tower-square-top-roof-high",
					"castle/tower-slant-roof"],
				"sky_n": 34,
				"cover": "mini-dungeon/barrel", "cover_h": 0.9,
			}
		_:
			return {
				"wall": ["prototype/wall-low"], "wall_s": 1.0,
				"wall_post": "prototype/column",
				"sky": ["prototype/column"], "sky_n": 12,
				"cover": "prototype/crate", "cover_h": 0.6,
			}

# --- per-region mid-ground dressing ---------------------------------------

## The three bands the TALL scatter passes are allowed to use: west wall, east
## wall, north wall. Anything with a silhouette lives against one of them; the
## middle of the room stays walkable, which matters more here than in 2D because
## set dressing does not collide and a player walking THROUGH a crate is a lot
## more visible in three dimensions.
##
## The SOUTH band is deliberately not in this list. At pitch -56 degrees and
## 21 units out the camera sits about 3.6 units beyond the south wall, so the
## bottom strip of the room is the one place where a 3-unit prop stands between
## the lens and the player. Only `_south_rect` may be dressed, and only with
## things shorter than about 0.7 units (this is also why the south border ring
## is built at RING_S_SCALE).
static func _edge_rects(w: float, h: float) -> Array:
	return [
		Rect2(40.0, 62.0, 250.0, h - 300.0),
		Rect2(w - 290.0, 62.0, 250.0, h - 300.0),
		Rect2(290.0, 62.0, w - 580.0, 180.0),
	]

## The near band, for ground litter only. `_keep_clear` already holds the boss
## arena out of it at 250px, which is what stops a fight being dressed over.
static func _south_rect(w: float, h: float) -> Rect2:
	return Rect2(120.0, h - 178.0, w - 240.0, 134.0)

static func _dress_region(parent: Node3D, ctx: Dictionary) -> void:
	match str(ctx["id"]):
		"dependency_district": _dress_dependency(parent, ctx)
		"stackoverflow_ruins": _dress_ruins(parent, ctx)
		"api_bazaar": _dress_bazaar(parent, ctx)
		"cloud_district": _dress_cloud(parent, ctx)
		"open_source_wildlands": _dress_wildlands(parent, ctx)
		"corporate_enterprise": _dress_corporate(parent, ctx)
		"gpu_mines": _dress_mines(parent, ctx)
		"production": _dress_production(parent, ctx)
		"token_vault": _dress_vault(parent, ctx)

## `n` copies of `key` spaced along a straight line in map px — how conveyor
## lines, shelf aisles, server banks and colonnades get built. `h` is a HEIGHT
## in world units, not a scale factor: a CEILING by default (`_cap`), or a
## target when `grow` says the run is architecture (`_fit`).
static func _run(parent: Node3D, key: String, from: Vector2, to: Vector2, n: int,
		yaw: float, h: float, tint: Color = Color.WHITE, grow: bool = false) -> void:
	if n <= 0:
		return
	var s := _size_for(key, h, grow)
	for i in n:
		var t := float(i) / maxf(1.0, float(n - 1))
		place(parent, key, from.lerp(to, t), yaw, s, tint)

# --- dependency district ---------------------------------------------------

static func _dress_dependency(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var warm: Color = ctx["warm"]

	# The packing line along the north wall — the region's one straight, man-made
	# edge, and the reason the room reads as a depot instead of a yard. 7 pieces.
	_run(parent, "factory/conveyor-long", Vector2(430, 122), Vector2(880, 122), 4, 0.0, 0.45)
	place(parent, "factory/hopper-high-round", Vector2(384, 122), 0.0,
		_cap("factory/hopper-high-round", 1.5))
	place(parent, "factory/scanner-high", Vector2(922, 124), PI * 0.5,
		_cap("factory/scanner-high", 1.3))
	# The arm is really 3.0u tall (the manifest says 1.0 and the manifest is
	# wrong — see `_model_aabb`), so at 1.1 it stood three and a third units over
	# a 0.9u player. Capped at 1.8, it is a machine again.
	place(parent, "factory/robot-arm-b", Vector2(650, 178), PI,
		_cap("factory/robot-arm-b", 1.8))

	# Pipework down ONE flank (3 pieces). There used to be a matching run down
	# the east wall: two identical lines facing each other across an empty room is
	# symmetry, not fiction, and it cost five placements to say nothing twice.
	_run(parent, "factory/pipe-large-long", Vector2(78, 340), Vector2(78, 660), 3, PI * 0.5, 0.7)
	# The crane and the truck live OUTSIDE the north wall: they are three units
	# tall, and the only band of this room that can carry a three-unit
	# silhouette without standing between the camera and the player is the one
	# behind the far wall. Backdrop, so they take the backdrop's value.
	var band := _band_tone(ctx["base"], ctx["floor"])
	var crane := place(parent, "factory/crane", Vector2(1130, -150), -PI * 0.5,
		_fit("factory/crane", 4.2), _tint_to(band, "factory/crane"), 0.0, 0.0, true)
	var truck := place(parent, "retro-urban/truck-grey-cargo", Vector2(210, -120), 0.28,
		_cap("retro-urban/truck-grey-cargo", 1.1),
		_tint_to(band, "retro-urban/truck-grey-cargo"), 0.0, 0.0, true)
	# Band value AND band shadow rules: these two stand where the sky ring
	# stands, so like the ring they cast nothing into the room.
	if crane != null:
		_no_shadow(crane)
	if truck != null:
		_no_shadow(truck)

	# Cargo against the walls, hazard kit on the floor: 9 + 3 + 2, and then the
	# room is finished. LAW 4's "the rest is clean floor" is the point of the
	# whole budget — a depot reads as a depot from one aisle of crates.
	for r: Rect2 in _edge_rects(w, h):
		scatter(parent, ctx, ["factory/box-large", "factory/box-long", "factory/box-wide",
			"prototype/crate", "retro-urban/pallet"], 3, r, 0.55, 0.6)
	scatter(parent, ctx, ["factory/warning-orange", "factory/cone",
		"retro-urban/detail-barrier-type-a"], 3,
		Rect2(140, 200, w - 280, h - 340), 0.5, 0.7)
	scatter(parent, ctx, ["retro-urban/pallet", "prototype/crate"], 2,
		_south_rect(w, h), 0.35, 0.5)

	motes(parent, Vector2(w * 0.5, h * 0.5), warm, 14, Vector3(9.0, 1.2, 7.0), 0.16, 1.0)

static func _focal_dependency(parent: Node3D, ctx: Dictionary) -> void:
	# The node_modules heap: 900 MB of transitive dependencies, stacked.
	#
	# Interactable3D already stands a three-crate stack on the prop_node_modules
	# anchor (3D_BIBLE §7), so that stack is the heap's crown and this is the
	# spill EAST of it. East only, because the west is spoken for: the Localhost
	# door at (250,392) — RegionBuilder._crate_ok keeps crates 120px off it,
	# the same rule the 2D heap obeys — and the two demon posts at (188,252)
	# and (286,246), which must not spawn inside a crate. The offsets also
	# clear the focal's own token cluster ((344,335) is the nearest coin) by a
	# crate's edge, so no reward is buried in the thing it rewards you for.
	var accent: Color = ctx["accent"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var anchor := _flavor_pos(str(ctx["id"]), "prop_node_modules", ctx["focal"])
	# [dx, dy, base height, scale] — box-large is 0.55u tall, so each tier sits
	# on the one below at its own scale (1.15 * 0.55 = 0.63, + 0.55 = 1.18).
	for crate: Array in [
			[104.0, -80.0, 0.0, 1.15], [104.0, 0.0, 0.0, 1.15], [104.0, 80.0, 0.0, 1.15],
			[188.0, -40.0, 0.0, 1.15], [188.0, 40.0, 0.0, 1.15],
			[104.0, -40.0, 0.63, 1.0], [104.0, 40.0, 0.63, 1.0], [188.0, 0.0, 0.63, 1.0],
			[104.0, 0.0, 1.18, 0.85]]:
		var at := anchor + Vector2(float(crate[0]), float(crate[1]))
		if not RegionBuilder._crate_ok(at):
			continue
		place(parent, "factory/box-large", at, rng.randf_range(-0.12, 0.12),
			float(crate[3]), Color.WHITE, float(crate[2]))
	# The install-bay readout: clear of the packing line's conveyors (which
	# reach y 154) and of the heap's north crate (from y 183), picture on its
	# face rather than inside its cabinet. THE one lit surface of this set-piece.
	var screen := anchor + Vector2(200, -110)
	var screen_s := _cap("factory/screen-wide", 1.0)
	place(parent, "factory/screen-wide", screen, 0.0, screen_s)
	panel(parent, screen + Vector2(0, _front("factory/screen-wide", screen_s)),
		Vector3(1.05, 0.62, 0.06), accent, 1.5, 0.0, 0.72)
	light(ctx, anchor + Vector2(104, -40), accent, 1.1, 9.0, true, 2.4)

# --- stackoverflow ruins ---------------------------------------------------

static func _dress_ruins(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]

	# Rows of dead questions. A graveyard is ONE repeated silhouette, and the
	# reading of it does not improve past about a dozen stones — the old 62
	# placements made a rockfall of it and buried the accepted answer they were
	# supposed to lead the eye to. 12 stones, 4 pieces of debris, 4 crypts.
	var stones := ["graveyard/gravestone-round", "graveyard/gravestone-cross",
		"graveyard/gravestone-bevel", "graveyard/gravestone-broken",
		"graveyard/gravestone-decorative", "graveyard/gravestone-wide"]
	for r: Rect2 in _edge_rects(w, h):
		scatter(parent, ctx, stones, 3, r, 0.7, 0.8)
	scatter(parent, ctx, stones, 3, Rect2(150, 260, w - 300, h - 400), 0.55, 0.7)
	# `graveyard/grave` is gone: it is a mound of loose SOIL, reads (0.80, 0.48,
	# 0.33) and at 1.3 it was the "orange spotted boulder / placeholder blob" the
	# critic found in the middle of the floor.
	scatter(parent, ctx, ["graveyard/debris", "graveyard/rocks",
		"graveyard/urn-round", "graveyard/cross-wood"], 4,
		Rect2(80, 200, w - 160, h - 300), 0.35, 0.5)
	scatter(parent, ctx, ["graveyard/crypt-small", "graveyard/crypt"], 4,
		Rect2(60, 180, w - 120, 500), 1.0, 1.8)
	scatter(parent, ctx, ["graveyard/debris", "graveyard/rocks"], 2,
		_south_rect(w, h), 0.25, 0.4)

	# Two lamp posts at the room's waist, and ONE of them is lit. Eight posts
	# with eight omnis is a lit street; one working lamp and one that is not is a
	# graveyard, costs a single light out of the six, and leaves the fight floor
	# dark enough for the accepted answer to be the brightest thing in the room.
	# (The pines went with the other six: they are on the horizon in `sky`, where
	# a tree a player can walk through belongs.)
	# The posts read (0.43, 0.65, 0.52) out of the box — a GREEN lamp post in a
	# gold-and-copper graveyard, which is exactly what the critic named. They go
	# through `place()`'s desaturation like everything else now; only the lit
	# lamp itself carries a hue, and that hue is this region's ACCENT.
	for k: float in [1.0, -1.0]:
		var x := w * 0.5 + k * (w * 0.5 - 86.0)
		place(parent, "graveyard/lightpost-single", Vector2(x, 470.0),
			PI * 0.5 * k, _cap("graveyard/lightpost-single", 2.2))
	light(ctx, Vector2(92, 470), accent, 0.8, 8.0, false, 1.8)
	motes(parent, Vector2(w * 0.5, h * 0.55), accent, 12, Vector3(9.0, 1.4, 7.0), 0.1, 1.4)

static func _focal_ruins(parent: Node3D, ctx: Dictionary) -> void:
	# The Accepted Answer. Green tick, 4,102 upvotes, deprecated in 2019.
	#
	# Interactable3D places the answer itself — prop_accepted's cross at
	# (640,236), 22px south of the focal — so this is the monument BEHIND it:
	# an altar slab whose south edge stops 3px short of that cross, the great
	# cross standing on the slab, and the obelisks, lanterns and candles fanned
	# around both. Nothing here stands on the small cross.
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	var altar := f + Vector2(0, -34)
	# The one thing in this room allowed past the prop caps, because it is the
	# focal: a 1.9u monument on a 0.98u slab, which is twice the player and reads
	# as a monument from anywhere in the room.
	var altar_s := _fit("graveyard/altar-stone", 0.5)
	place(parent, "graveyard/altar-stone", altar, 0.0, altar_s)
	# Stone, desaturated like everything else (LAW 2): the accent light on it is
	# what makes it the brightest thing here, not a warm-white albedo request.
	place(parent, "graveyard/gravestone-cross-large", altar, 0.0,
		_fit("graveyard/gravestone-cross-large", 1.9), Color.WHITE,
		_height_of("graveyard/altar-stone") * altar_s)
	for k: float in [1.0, -1.0]:
		place(parent, "graveyard/pillar-obelisk", f + Vector2(k * 108.0, 22.0), 0.0,
			_cap("graveyard/pillar-obelisk", 1.4))
		place(parent, "graveyard/lantern-candle", f + Vector2(k * 120.0, 62.0), 0.0,
			_cap("graveyard/lantern-candle", 0.5))
		place(parent, "graveyard/candle", f + Vector2(k * 30.0, 74.0), 0.0,
			_cap("graveyard/candle", 0.25))
	# The brazier is the set-piece's one lit surface and the room's one WARM
	# thing: a fire, which is the only kind of prop LAW 3 lets glow.
	place(parent, "graveyard/fire-basket", f + Vector2(0, 96), 0.0,
		_cap("graveyard/fire-basket", 0.3))
	panel(parent, f + Vector2(0, 96), Vector3(0.34, 0.05, 0.34), warm, 1.5, 0.0, 0.22)
	light(ctx, f + Vector2(0, 40), accent, 1.2, 9.5, true, 2.4)

# --- api bazaar ------------------------------------------------------------

static func _dress_bazaar(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]

	# Two shelf aisles down the sides, a run of freezers across the top: the
	# market has lanes, and the lanes point at the doors. 3 + 3 + 4 = 10.
	# The west aisle stops at 540 rather than running the wall: the 2D room stands
	# cover blocks there at (170,340) and (150,600), and a shelf through a barrier
	# is a shelf the player fights around without ever seeing.
	_run(parent, "mini-market/shelf-bags", Vector2(126, 400), Vector2(126, 540), 3, PI * 0.5, 1.6)
	# 360..640, not 300..660: at 300 the first shelf stood on the rate limiter's
	# post at (1120,300) and at 660 the last one stood on the reseller's feet.
	_run(parent, "mini-market/shelf-boxes", Vector2(1154, 360), Vector2(1154, 640), 3, -PI * 0.5, 1.6)
	_run(parent, "mini-market/freezers-standing", Vector2(360, 122), Vector2(920, 122), 4, 0.0, 1.1)

	# Four awnings, desaturated. An awning is CANVAS: it belongs to the room's
	# silhouette, not to its colour, and the accent/warm it used to be painted in
	# was two more saturated hues in a frame that already has three.
	for i in 4:
		var x := 300.0 + float(i) * 224.0
		place(parent, "city-commercial/detail-awning", Vector2(x, 182), PI,
			_fit("city-commercial/detail-awning", 0.5), Color.WHITE, 1.15)
	scatter(parent, ctx, ["mini-market/display-fruit", "mini-market/display-bread",
		"mini-market/freezer", "mini-market/cash-register", "mini-market/shelf-end"], 5,
		Rect2(70, 170, w - 140, h - 260), 0.5, 0.75)
	# `food/pizza-box` ships OPEN and is nearly a metre across the lid; it is not
	# market dressing at this camera, it is a white slab on the floor. Dropped.
	scatter(parent, ctx, ["mini-market/shopping-cart", "mini-market/shopping-basket",
		"food/soda-can"], 3,
		Rect2(140, 220, w - 280, h - 340), 0.3, 0.45)
	scatter(parent, ctx, ["city-commercial/detail-parasol-a", "city-commercial/detail-parasol-b"],
		2, Rect2(60, 180, w - 120, 500), 1.5, 1.9)

	# The market's own neon: ONE sign per flank at the room's waist, on the two
	# hues this region owns. Ten aisle panels and four omnis is what "the
	# loudest region and it is allowed to be" turned into, and v2 supersedes it:
	# loud is a hue on two surfaces, not a hue on twenty.
	# These are SIGNS, so they stop at SIGN_E_MAX like the north-wall bank: the
	# room's screen-energy surfaces are the pitch board and nothing else.
	panel(parent, Vector2(104, 470), Vector3(0.08, 0.5, 0.9), accent, SIGN_E_MAX, 0.0, 2.1,
		SIGN_E_MAX)
	panel(parent, Vector2(w - 104, 470), Vector3(0.08, 0.5, 0.9), warm, SIGN_E_MAX, 0.0, 2.1,
		SIGN_E_MAX)
	light(ctx, Vector2(150, 470), accent, 0.9, 8.0, false, 2.1)

static func _focal_bazaar(parent: Node3D, ctx: Dictionary) -> void:
	# The main pitch: unlimited tokens, 40% off, no questions.
	#
	# prop_api_stall's own register (Interactable3D) stands at (566,342), 74px
	# west of the focal, so the stall is built around both: the pitch's register
	# at the focal, the shelves and parasols pushed out to 140 and 210px where
	# they clear that second register and the coin the cluster drops by it.
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	place(parent, "mini-market/cash-register", f + Vector2(-4, -4), 0.0,
		_cap("mini-market/cash-register", 0.6))
	place(parent, "mini-market/shelf-bags", f + Vector2(-140, 30), 0.0,
		_cap("mini-market/shelf-bags", 1.6))
	place(parent, "mini-market/shelf-boxes", f + Vector2(140, 30), 0.0,
		_cap("mini-market/shelf-boxes", 1.6))
	# The stall canopy is the ONE thing here allowed past a prop cap, and the one
	# thing carrying the ACCENT: it is the pitch you are meant to walk toward.
	place(parent, "city-commercial/detail-awning", f + Vector2(0, -46), PI,
		_fit("city-commercial/detail-awning", 0.7), accent, 1.45)
	place(parent, "city-commercial/detail-parasol-b", f + Vector2(-210, 10), 0.0,
		_fit("city-commercial/detail-parasol-b", 1.9), warm)
	place(parent, "city-commercial/detail-parasol-a", f + Vector2(210, 10), 0.0,
		_fit("city-commercial/detail-parasol-a", 1.9), warm)
	# The pitch board: one lit face, with the gold rule under it as its trim.
	panel(parent, f + Vector2(0, -54), Vector3(1.6, 0.5, 0.07), accent, 1.6, 0.0, 2.15)
	panel(parent, f + Vector2(0, -54), Vector3(1.7, 0.06, 0.08), warm, 1.2, 0.0, 1.86)
	light(ctx, f + Vector2(0, -20), accent, 1.15, 9.5, true, 2.4)

# --- cloud district --------------------------------------------------------

static func _dress_cloud(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]

	# ONE server aisle, cold and straight. The second row behind it was the same
	# nine silhouettes again at the same height — depth the camera cannot read
	# and nine placements it cost to say nothing.
	var rack_s := _fit("space-station/container-tall", RACK_H)
	_run(parent, "space-station/container-tall", Vector2(230, 150), Vector2(1050, 150),
		8, 0.0, RACK_H, Color.WHITE, true)
	# Only the WEST pipe run survives. The east one ran down the salesperson's
	# wall at (1196,700) and was the mirror of a line the player had already
	# read; the fourteen-piece rail across the room's waist went with it, because
	# a handrail drawn in front of the racks is a second horizontal line
	# competing with the aisle that IS this room's line.
	_run(parent, "space-station/pipe", Vector2(78, 340), Vector2(78, 700), 4, 0.0, 0.6)

	scatter(parent, ctx, ["space-station/computer", "space-station/computer-wide",
		"space-station/computer-system"], 3,
		Rect2(70, 250, w - 140, h - 340), 0.6, 0.75)
	scatter(parent, ctx, ["space-station/container", "space-station/container-wide",
		"space-station/container-flat"], 2,
		Rect2(60, 240, w - 120, h - 330), 0.6, 0.75)
	scatter(parent, ctx, ["modular-space/cables", "space-station/container-flat"],
		1, _south_rect(w, h), 0.3, 0.45)

	# Rack status LEDs: one strip per cabinet, on its camera-facing face. These
	# ARE screens (LAW 7 lets a screen carry the accent on its lit surface), but
	# thirty-six of them at energy 5 was a light field, not a data centre. Eight,
	# at screen energy, under the aisle's single motivated omni.
	var led := BoxMesh.new()
	led.size = Vector3(0.55, 0.05, 0.06)
	# On the racks' camera-facing face, not 13px inside them.
	var face := _front("space-station/container-tall", rack_s)
	var xf: Array = []
	for i in 8:
		var x := 230.0 + float(i) * (820.0 / 7.0)
		xf.append(Transform3D(Basis(), Map3D.to3d(Vector2(x, 150.0 + face), 0.52)))
	# 1.4, not 2.4: at 2.4 these strips came back WHITE, and the critic read the
	# result as "a flat pure-white rectangle on the floor at the base of every
	# barrel" — the barrels are the racks and the rectangles are these.
	_mm_mesh(parent, led, xf, Map3D.matte(accent, 1.4))
	light(ctx, Vector2(w * 0.5, 196.0), accent, 0.85, 9.0, false, 1.9)

static func _focal_cloud(parent: Node3D, ctx: Dictionary) -> void:
	# The invoice altar. It is bigger than last month's invoice altar.
	#
	# The invoice is prop_invoice's own computer (Interactable3D) at (884,672),
	# 24px south of the focal, and the focal's token cluster hangs 96px north
	# of it at x 788 and 932. So: a screen behind the invoice narrow enough to
	# pass between the coins, the display table and a console on the floor
	# either side of it, and nothing standing where the coins bob or the
	# invoice sits.
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	var screen := f + Vector2(0, -38)
	# The CABINET is a prop and does not glow (it used to be emissive over its
	# whole body at energy 2.5, which is a light box with a picture stuck on it);
	# the PICTURE on its front face is the set-piece's one lit surface.
	var wall_s := _fit("space-station/display-wall", 1.2)
	place(parent, "space-station/display-wall", screen, 0.0, wall_s)
	panel(parent, screen + Vector2(0, _front("space-station/display-wall", wall_s)),
		Vector3(0.95, 0.85, 0.06), accent, 1.6, 0.0, 0.6)
	var table := f + Vector2(-124, 52)
	var table_s := _cap("space-station/table-display", 0.8)
	place(parent, "space-station/table-display", table, 0.3, table_s)
	# The table-display's own top, now that place() grounds it. A hologram is a
	# screen, so it is allowed emission — at a screen's energy, not a sun's.
	place(parent, "space-station/table-display-planet", table, 0.3,
		_cap("space-station/table-display-planet", 0.35), warm,
		_height_of("space-station/table-display") * table_s, 1.4)
	place(parent, "space-station/computer-system", f + Vector2(116, 42), -0.4,
		_cap("space-station/computer-system", 0.75))
	light(ctx, f + Vector2(0, 12), accent, 1.15, 10.0, true, 2.4)

# --- open source wildlands -------------------------------------------------

static func _dress_wildlands(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var warm: Color = ctx["warm"]

	# A clearing with a wood around it, not a wood with a clearing lost in it.
	# 119 placements went in here — thirty-four of them FLOWERS, which at this
	# camera is confetti on the ground and is precisely LAW 4's "floor overlays:
	# zero" wearing a mesh. 9 trees on the edges, 6 bushes, 6 rocks and logs,
	# 3 near the camera. The canopy the player reads is on the horizon (`sky`).
	var trees := ["nature/tree_default", "nature/tree_oak", "nature/tree_pineRoundC",
		"nature/tree_detailed", "mini-forest/tree", "mini-forest/tree-high"]
	for r: Rect2 in _edge_rects(w, h):
		scatter(parent, ctx, trees, 3, r, 2.5, 3.0)
	scatter(parent, ctx, ["nature/plant_bushLarge", "nature/plant_bushDetailed",
		"nature/plant_bushSmall", "mini-forest/plant"], 6,
		Rect2(80, 190, w - 160, h - 280), 0.3, 0.4)
	scatter(parent, ctx, ["nature/rock_largeA", "nature/rock_tallC",
		"mini-forest/stones", "nature/log", "nature/log_stack", "nature/stump_round"], 6,
		Rect2(80, 200, w - 160, h - 300), 0.3, 0.5)
	scatter(parent, ctx, ["nature/plant_bushSmall", "nature/log", "nature/stump_round"],
		3, _south_rect(w, h), 0.2, 0.3)

	motes(parent, Vector2(w * 0.5, h * 0.5), warm, 12, Vector3(9.5, 1.6, 7.0), 0.14, 1.3)

static func _focal_wildlands(parent: Node3D, ctx: Dictionary) -> void:
	# The maintainer's campfire. Nine years, one person, forty thousand deps.
	#
	# The fire sits WEST of the focal: prop_sponsor's chest (Interactable3D)
	# is 32px north of it and the maintainer himself 40px south, and a ring of
	# stones 0.9u across does not fit between a chest and a pair of feet. 46px
	# west clears the chest by 2px and the man by half a unit, and the log he
	# sits on goes with it. The flag steps north off the legacy system's post
	# at (1148,620).
	var f: Vector2 = ctx["focal"]
	var warm: Color = ctx["warm"]
	var accent: Color = ctx["accent"]
	var fire := f + Vector2(-46, 6)
	place(parent, "nature/campfire_stones", fire, 0.0, 1.6)
	place(parent, "nature/campfire_logs", fire, 0.35, 1.6, warm, 0.04, 1.4)
	# The tent is (0.57, 0.48, 0.70) untouched — a violet canvas, which is the
	# Vault's WARM and not this region's anything. `place()` desaturates it now.
	place(parent, "mini-forest/tent", f + Vector2(-156, -4), 0.5,
		_cap("mini-forest/tent", 1.0))
	place(parent, "nature/log_large", f + Vector2(-40, 92), PI * 0.5,
		_cap("nature/log_large", 0.45))
	place(parent, "nature/log_large", f + Vector2(96, 40), PI * 0.5,
		_cap("nature/log_large", 0.45))
	place(parent, "mini-forest/flag", f + Vector2(96, -90), 0.0,
		_cap("mini-forest/flag", 1.4), accent)
	# The fire: this region's ONE bright thing, and the only warm light in a
	# wood at night. Embers, not a bonfire — LAW 9 keeps rest quiet.
	panel(parent, fire, Vector3(0.26, 0.08, 0.26), warm, 1.5, 0.0, 0.09)
	motes(parent, fire, warm, 12, Vector3(0.4, 0.2, 0.4), 1.4, 0.3)
	light(ctx, fire, warm, 1.2, 8.0, true, 1.9)

# --- corporate enterprise --------------------------------------------------

static func _dress_corporate(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]

	# Desk pods facing the stage, because of course they are. The furniture kit is
	# authored at the same 1u = 2 m as everything else, so a desk is scale 1.0 and
	# its top is at y 0.384. Rows at 390/550/710, not 300/472/644: the top row
	# stood on the cover blocks at (160,340) and (1170,340).
	#
	# Three pods, twelve pieces — five pods and fifty-two scattered props was an
	# office nobody could see across. The screens do NOT glow: they used to carry
	# emission 1.4 over the whole model, which lights the plastic as well as the
	# picture — five monitors' worth of accent spread across a room that is
	# allowed two bright things. They are dark glass now, which is what an open
	# plan looks like at night and what makes the stage read as the lit thing.
	for row in 3:
		var y := 390.0 + float(row) * 160.0
		# 120 on the west, not 150: the wildlands door is at (216,452) and a desk
		# at 150 ran its far end into the arch. Two pods west and one east, and
		# the east one is the SOUTH row — the old grid's east middle seat was
		# skipped because the GPU Mines door at (1058,568) is exactly there, and
		# that hole is still honoured.
		var east := row == 2
		var x := w - 150.0 if east else 120.0
		var yaw := PI if east else 0.0
		var desk_top := _height_of("furniture/desk")
		place(parent, "furniture/desk", Vector2(x, y), yaw, _cap("furniture/desk", 0.75))
		place(parent, "furniture/chairDesk", Vector2(x, y + 44.0), PI,
			_cap("furniture/chairDesk", 0.9))
		# The monitor was the one piece of this pod drawn OVER 1.0, at 1.2, which
		# put a 0.35u screen on a 0.38u desk. Capped at a monitor's 0.45.
		place(parent, "furniture/computerScreen", Vector2(x, y - 4), yaw,
			_cap("furniture/computerScreen", 0.45), Color.WHITE, desk_top)
		place(parent, "furniture/computerKeyboard", Vector2(x, y + 10), yaw,
			_cap("furniture/computerKeyboard", 0.04), Color.WHITE, desk_top)
	_run(parent, "furniture/bookcaseClosed", Vector2(380, 116), Vector2(900, 116), 4, PI, 1.6)
	scatter(parent, ctx, ["furniture/pottedPlant", "furniture/plantSmall1",
		"furniture/plantSmall3"], 4, Rect2(80, 190, w - 160, h - 280), 0.5, 0.7)
	scatter(parent, ctx, ["furniture/loungeChair", "furniture/tableCoffeeGlass",
		"furniture/sideTable"], 3,
		Rect2(90, 230, w - 180, h - 340), 0.45, 0.8)
	scatter(parent, ctx, ["furniture/books", "furniture/laptop"],
		1, _south_rect(w, h), 0.12, 0.2)

	# One lit noticeboard on the north wall, EAST of centre — `_build_signage`
	# hangs the region's monitor bank at x 390-546 on the same wall, and two
	# banks of screens a metre apart is one bank drawn twice. Four of them with
	# an omni each is four motivated sources in a room whose whole joke is that
	# everyone is looking at one screen. It shares the bank's light.
	panel(parent, Vector2(900.0, 96.0), Vector3(1.1, 0.62, 0.06), accent, SIGN_E_MAX,
		0.0, 0.6, SIGN_E_MAX)

static func _focal_corporate(parent: Node3D, ctx: Dictionary) -> void:
	# The all-hands stage. Q3 was transformational and Q4 will be too.
	#
	# Squeezed on purpose: the SVP stands 44px south of the focal, the focal's
	# three coins bob 96px north of it, and neither may end up inside a dais.
	# So the riser is a low step (prototype/floor-thick at 1.5x: 0.3u, which a
	# coin hovering at 0.55 clears and a walking player reads as a kerb), the
	# screen stands on it 15px west of centre where it clears the nearest coin,
	# and the lectern is off the riser altogether.
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	var deck := _height_of("prototype/floor-thick") * 1.5
	var stage := f + Vector2(-30, -20)
	place(parent, "prototype/floor-thick", stage, 0.0, 1.5, warm)
	var screen := stage + Vector2(0, -24)
	# Cabinet dark, picture lit: the whole room is looking at ONE surface. The
	# screen is the focal, so it is allowed its 1.1u — nothing else here is.
	var wall_s := _fit("space-station/display-wall-wide", 1.1)
	place(parent, "space-station/display-wall-wide", screen, 0.0, wall_s, Color.WHITE, deck)
	panel(parent, screen + Vector2(0, _front("space-station/display-wall-wide", wall_s)),
		Vector3(1.3, 0.8, 0.06), accent, 1.6, 0.0, deck + 0.55)
	for k: float in [1.0, -1.0]:
		place(parent, "mini-arena/banner", f + Vector2(k * 156.0, -46.0), 0.0,
			_fit("mini-arena/banner", 1.6), accent)
		place(parent, "furniture/lampSquareFloor", f + Vector2(k * 118.0, 52.0), 0.0,
			_cap("furniture/lampSquareFloor", 0.9))
	place(parent, "space-station/table", f + Vector2(-124, -4), 0.0,
		_cap("space-station/table", 0.45))
	light(ctx, f + Vector2(0, 10), accent, 1.2, 10.0, true, 2.6)

# --- gpu mines -------------------------------------------------------------

static func _dress_mines(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]

	# ONE rig bank along the north, where the 2D room posts its memory leaks: the
	# thing worth taking is the thing that is defended. Six racks became five,
	# and the two status strips per rack became one — twelve strips at energy 5
	# was the brightest thing in a room whose focal is supposed to be a hole full
	# of fire.
	# `factory/machine-fortified`, not `space-station/container-tall`: the Cloud
	# already owns that silhouette in a straight line along ITS north wall, and
	# two regions wearing the same set-piece is one of the things the critic
	# counted. A mine rents machines; it does not rent server cabinets.
	var rig := "factory/machine-fortified"
	var rig_s := _cap(rig, 1.35)
	var face := 128.0 + _front(rig, rig_s)
	for i in 5:
		var x := 300.0 + float(i) * 140.0
		place(parent, rig, Vector2(x, 128), 0.0, rig_s)
		panel(parent, Vector2(x, face), Vector3(0.5, 0.05, 0.06), accent, 1.4, 0.0, 0.7)
	light(ctx, Vector2(w * 0.5, 176.0), warm, 0.8, 8.0, false, 1.8)

	# Cogs and pipework half-buried in the rock; the mine is a machine that
	# happens to be underground. 4 cogs, one pipe run, 8 rocks, 2 crystals.
	# A cog is 1.00 x 0.22: at 2.1 it was a two-unit gear lying on the floor
	# beside a 0.9u player. `_cap` reads its real bounds and the footprint guard
	# in `_fit` stops a flat model being blown up to reach a height at all.
	scatter(parent, ctx, ["factory/cog-a", "factory/cog-b", "factory/cog-c",
		"factory/cog-d", "factory/cog-e"], 4,
		Rect2(60, 190, w - 120, h - 280), 0.22, 0.3)
	# Timber, not the factories' pipework: `factory/pipe-large-long` runs down
	# the west wall in BOTH Dependency and Production already, and a third copy
	# of it is the shared set-piece the critic named.
	_run(parent, "mini-dungeon/column", Vector2(78, 340), Vector2(78, 760), 4, 0.0, 1.6,
		Color.WHITE, true)
	scatter(parent, ctx, ["tower-defense/detail-crystal", "tower-defense/detail-crystal-large"],
		2, Rect2(80, 200, w - 160, h - 300), 0.4, 0.55)
	scatter(parent, ctx, ["mini-dungeon/rocks", "mini-dungeon/stones", "nature/rock_largeC",
		"tower-defense/detail-rocks-large", "graveyard/rocks"], 6,
		Rect2(70, 190, w - 140, h - 290), 0.4, 0.55)
	scatter(parent, ctx, ["tower-defense/detail-rocks", "mini-dungeon/stones"], 3,
		_south_rect(w, h), 0.2, 0.32)

	motes(parent, Vector2(w * 0.5, h * 0.5), warm, 14, Vector3(9.5, 1.6, 7.0), 0.5, 0.8)

static func _focal_mines(parent: Node3D, ctx: Dictionary) -> void:
	# The heat pit. Everything expensive in this game comes out of this hole.
	#
	# 32px south of the focal, and small: the focal's three coins hang 96px
	# north of it and the nearest, (468,521), is only 49px from the anchor —
	# a rim of 1.15u boulders at radius 62 put that coin inside a rock. The
	# rim is 0.6u rocks at radius 42 around a centre 32px lower, which clears
	# the coin's bottom edge at any yaw, and the crystal is sized to match.
	var f: Vector2 = ctx["focal"]
	var warm: Color = ctx["warm"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var pit := f + Vector2(0, 32)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		place(parent, "mini-dungeon/rocks", pit + Vector2(cos(a) * 80.0, sin(a) * 42.0),
			rng.randf_range(0.0, TAU), _cap("mini-dungeon/rocks", 0.35))
	# A CRYSTAL CLUSTER with an ember light in it, which is what this focal was
	# always supposed to be. What the pass-3 frame actually showed was "a flat
	# peach faceted blob with three red spheres": the great crystal at emission
	# 2.4 clipped to white-peach, the 1.3 x 0.9 emissive slab under it lit the
	# floor like a hotplate, and the two flanking crystals — which read
	# (0.79, 0.47, 0.92) untouched, a saturated violet — took the ember ACCENT
	# on top of that and came out as spheres of pure red.
	#
	# Now: one WARM emissive core at 1.4 inside a cluster of five, its flanks
	# desaturated like every other prop, one OmniLight doing the actual lighting,
	# and eight slow embers. Nothing here is white and nothing is a slab.
	place(parent, "tower-defense/detail-crystal-large", pit, 0.4,
		_fit("tower-defense/detail-crystal-large", 1.1), warm, 0.0, 1.4)
	for k: float in [1.0, -1.0]:
		place(parent, "tower-defense/detail-crystal", pit + Vector2(k * 44.0, 22.0),
			k * 0.6, _cap("tower-defense/detail-crystal", 0.55))
		place(parent, "tower-defense/detail-crystal", pit + Vector2(k * 30.0, -26.0),
			-k * 0.9, _cap("tower-defense/detail-crystal", 0.4))
	motes(parent, pit, warm, 8, Vector3(0.5, 0.3, 0.4), 0.9, 0.35)
	light(ctx, pit, warm, 0.9, 5.0, true, 1.4)

# --- production ------------------------------------------------------------

static func _dress_production(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var accent: Color = ctx["accent"]

	# The line runs down both flanks with the pistons and hoppers that feed it.
	# The middle of the room stays open: this is a boss room.
	# The lines hug the walls at x 80 and 1196 (a conveyor is 1u wide): at 100
	# the west line ran through the cover block at (150,600), at 1180 the east
	# line's edge landed on the hallucination's post at (1148,560). The east
	# line also stops at 540, because the block at (1180,720) is the next
	# thing on that wall and a conveyor through a barrier is neither.
	_run(parent, "factory/conveyor-long-stripe", Vector2(80, 320), Vector2(80, 760),
		5, PI * 0.5, 0.45)
	_run(parent, "factory/conveyor-long-stripe", Vector2(1196, 320), Vector2(1196, 540),
		3, PI * 0.5, 0.45)
	place(parent, "factory/hopper-high-square", Vector2(80, 262), 0.0,
		_cap("factory/hopper-high-square", 1.5))
	place(parent, "factory/hopper-high-square", Vector2(1196, 262), 0.0,
		_cap("factory/hopper-high-square", 1.5))
	place(parent, "factory/piston-round", Vector2(80, 812), 0.0,
		_cap("factory/piston-round", 1.0))
	place(parent, "factory/piston-round", Vector2(1196, 812), 0.0,
		_cap("factory/piston-round", 1.0))
	_run(parent, "factory/catwalk-straight", Vector2(430, 118), Vector2(850, 118), 4, 0.0, 0.6)

	# The floor was carrying sixty-four placements, twenty-six of them accent-
	# and warm-tinted buttons, levers and indicators — a rainbow of controls in
	# the one room that has to read as an emergency. Six crates, and the middle
	# of the room stays open, because this is a boss room.
	scatter(parent, ctx, ["factory/box-large", "factory/box-wide", "prototype/crate",
		"retro-urban/pallet"], 4, Rect2(70, 190, w - 140, h - 290), 0.55, 0.6)
	scatter(parent, ctx, ["retro-urban/pallet", "factory/cone"], 2,
		_south_rect(w, h), 0.3, 0.45)

	# Rotating beacons, minus the rotation. TWO of them, flanking the war room,
	# on one omni: two red points say "incident" exactly as well as six do, and
	# they leave the frame somewhere dark to say it against.
	for k: float in [1.0, -1.0]:
		var p := Vector2(w * 0.5 + k * 430.0, h * 0.5 - 250.0)
		panel(parent, p, Vector3(0.2, 0.14, 0.2), accent, 1.5, 0.0, 1.55)
	light(ctx, Vector2(w * 0.5, h * 0.5 - 250.0), accent, 0.7, 10.0, false, 1.7)

static func _focal_production(parent: Node3D, ctx: Dictionary) -> void:
	# The war room. Nine dashboards, all of them red.
	#
	# prop_pager's own computer (Interactable3D) stands 88px south of the
	# focal and the focal's coins 96px north of it, so the screens hang 56px
	# north of the focal with their pictures on their faces, and the display
	# table is tucked west of the pager where it clears both the pager and
	# the coin at (904,301).
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	# Three dashboards, cabinets dark, pictures lit — ONE emissive plane each,
	# which is what a wall of screens actually is. The bodies used to glow at
	# 2.4 as well, so the war room was a slab of light with three brighter
	# rectangles inside it and no silhouette at all.
	var wall_s := _fit("space-station/display-wall-wide", 1.0)
	var face := _front("space-station/display-wall-wide", wall_s)
	for i in 3:
		var x := f.x + (float(i) - 1.0) * 108.0
		place(parent, "space-station/display-wall-wide", Vector2(x, f.y - 56.0), 0.0, wall_s)
		panel(parent, Vector2(x, f.y - 56.0 + face), Vector3(1.05, 0.7, 0.06), accent, 1.6,
			0.0, 0.55)
	place(parent, "space-station/table-display", f + Vector2(-40, 28), 0.0,
		_cap("space-station/table-display", 0.8))
	place(parent, "factory/screen-wide", f + Vector2(-190, 30), 0.5,
		_cap("factory/screen-wide", 1.0))
	place(parent, "factory/screen-wide", f + Vector2(150, 30), -0.5,
		_cap("factory/screen-wide", 1.0))
	place(parent, "factory/warning-traffic", f + Vector2(-220, 96), 0.0,
		_cap("factory/warning-traffic", 1.3), warm)
	place(parent, "factory/warning-traffic", f + Vector2(220, 96), 0.0,
		_cap("factory/warning-traffic", 1.3), warm)
	light(ctx, f + Vector2(0, 24), accent, 1.2, 10.0, true, 2.4)

# --- token vault -----------------------------------------------------------

static func _dress_vault(parent: Node3D, ctx: Dictionary) -> void:
	var w: float = ctx["w"]
	var h: float = ctx["h"]
	var warm: Color = ctx["warm"]

	# Colonnades down both flanks — the vault is the one room in the game with
	# architecture rather than equipment.
	# 240..760 on a 130 pitch, not 300..780 on 120: the old second column stood
	# exactly on the cover block at (1180,420). The lamps ride the column tops
	# (a column is 1.98u at 1.8x) rather than being cast inside them.
	# FIVE a side, not four: the pitch is what keeps a column off the cover block
	# at (1180,420) — four columns put one at y 413, inside it.
	for side: float in [116.0, 1164.0]:
		_run(parent, "mini-dungeon/column", Vector2(side, 240), Vector2(side, 760), 5,
			0.0, 2.2, Color.WHITE, true)
	# Two sconces, one per colonnade, at the room's waist — the vault's second
	# motivated source. Ten of them down both walls with four omnis was a
	# corridor of light with a treasure room somewhere inside it.
	for k: float in [1.0, -1.0]:
		panel(parent, Vector2(w * 0.5 + k * (w * 0.5 - 132.0), 500.0),
			Vector3(0.06, 0.32, 0.26), warm, 1.4, 0.0, 2.0)
	light(ctx, Vector2(160, 500), warm, 0.8, 9.0, false, 2.2)

	# castle/metal-gate is authored along Z (0.07 x 0.7); a quarter turn runs
	# the railings ALONG the north wall instead of five fins sticking out of it.
	# Three, 340..700, at y 90: the way home is a door in that wall at (884,96)
	# with a 200px keep-out, and the reserve's coin horseshoe reaches y 102.
	_run(parent, "castle/metal-gate", Vector2(340, 90), Vector2(700, 90), 3, PI * 0.5, 1.6)
	scatter(parent, ctx, ["mini-dungeon/chest", "mini-dungeon/barrel", "mini-dungeon/pot",
		"mini-dungeon/table"], 3, Rect2(70, 190, w - 140, h - 290), 0.45, 0.6)
	scatter(parent, ctx, ["mini-dungeon/stones", "mini-dungeon/rocks", "castle/flag"], 2,
		Rect2(80, 200, w - 160, 480), 0.45, 0.7)
	scatter(parent, ctx, ["mini-dungeon/stones", "mini-dungeon/pot"], 2,
		_south_rect(w, h), 0.3, 0.42)
	# The twenty accent-tinted floor coins are GONE. Eight real tokens are the
	# only gold points a player may see in this room (LAW 3: tokens are one of
	# the five bright things); twenty scenery coins that look exactly like them
	# and cannot be picked up is the worst hierarchy failure in the game.

static func _focal_vault(parent: Node3D, ctx: Dictionary) -> void:
	# The reserves. Everything the game has been counting, in one pile.
	#
	# prop_vault (Interactable3D: gate plus chest) stands at (640,296), 52px
	# south of the focal, so the pedestal is built 36px NORTH of the focal and
	# ends short of that door: a 2.1u plinth carrying the great gate along its
	# back edge and the reserve chest, with the loose coins in a horseshoe
	# round its north side — the old full ring's south arc ran straight
	# through the vault door.
	var f: Vector2 = ctx["focal"]
	var accent: Color = ctx["accent"]
	var warm: Color = ctx["warm"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var c := f + Vector2(0, -38)
	var plinth := _height_of("prototype/floor-thick") * 2.1
	# The plinth, the gate and the chest are all stone and metal under the accent
	# light — no off-white albedo requests (LAW 2: the only saturated things in
	# this room are its three hues, and the lamp already carries the gold).
	place(parent, "prototype/floor-thick", c, 0.0, 2.1)
	# castle/metal-gate is authored along Z; a quarter turn runs it along the
	# plinth's back edge, facing the camera.
	# THE VAULT'S FOCAL IS THE GATE AND THE CHEST, and they are the two things in
	# this room allowed past a prop cap: a 1.7u gate on the plinth's back edge
	# with the reserve chest in front of it, flanked by the colonnade's own
	# columns. Nothing else in the room is over a metre.
	place(parent, "castle/metal-gate", c + Vector2(0, -44), PI * 0.5,
		_fit("castle/metal-gate", 1.7), Color.WHITE, plinth)
	place(parent, "mini-dungeon/chest", c, 0.0, _fit("mini-dungeon/chest", 0.6),
		Color.WHITE, plinth)
	for k: float in [1.0, -1.0]:
		place(parent, "mini-dungeon/column", f + Vector2(k * 166.0, -8.0), 0.0,
			_fit("mini-dungeon/column", 2.2))
		# Banners hang 0.5u behind their origin, so a half turn 8px south of the
		# column's anchor drapes one down the column's camera-facing side.
		place(parent, "mini-dungeon/banner", f + Vector2(k * 166.0, 0.0), PI,
			_cap("mini-dungeon/banner", 1.0), warm)
	# The loose reserve. NOT emissive: a pickup token is gold and lit, so a piece
	# of scenery that is also gold and lit teaches the player that gold means
	# nothing. These are metal in the pedestal's light, and the eight real coins
	# in the room are the only ones that shine on their own.
	for i in 5:
		var a := PI + PI * float(i) / 4.0
		place(parent, "mini-dungeon/coin", c + Vector2(cos(a) * 106.0, sin(a) * 84.0),
			rng.randf_range(0.0, TAU), _cap("mini-dungeon/coin", 0.3), accent, 0.06)
	panel(parent, c + Vector2(0, -44), Vector3(1.6, 0.05, 0.06), accent, 1.6, 0.0, 1.85)
	light(ctx, c + Vector2(0, 20), accent, 1.2, 10.0, true, 2.4)
