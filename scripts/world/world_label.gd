extends Node2D
class_name WorldLabel
## The ONE way world text is drawn. Both builders route every sign, caption,
## plaque and screen readout through here.
##
## ROUND 7 — SUBTRACTION. What this class DRAWS was the second-loudest thing in
## the captured frames after the floors, and VISUAL_BIBLE_V2 LAW 4 describes the
## replacement in one line: "plain aliased text, 1px #000000@80% drop shadow
## offset (1,1). No plate, no accent bar, no leader line, no rounded rect."
##
## Deleted this round, in the order a viewer would have noticed them:
##
##   * the dark glass PLATE — a 6px-radius rounded rect at 88-94% opacity with a
##     hairline accent border and a 7px drop shadow, behind every caption. Thirty
##     of them in a room is thirty floating UI panels sitting in the world, and
##     it is why the localhost frame reads as a browser rather than as a flat;
##   * the overbright ACCENT BAR down the left edge of each plate, on additive
##     blend at 1.9x. Additive ink at 1.9 over a dark floor is a light source
##     (LAW 3 allows five, and none of them is a caption);
##   * the headline UNDERLIT BASE and the duplicated 1.7x overbright glow copy of
##     the title — a caption that blooms;
##   * the LEADER: a 1px elbow tick with a diamond terminator, drawn from a
##     displaced plate back toward its subject. It exists to explain a
##     displacement the ladder should not be making in the first place;
##   * the TITLE / SUBTITLE split with its hairline accent rule, a second font
##     size and a third text colour. Two registers and a divider is typography a
##     caption of four words has not earned;
##   * the BOB. LAW 9 lists what may move at rest — tokens, characters, the
##     waypoint, lights — and text is not on it. Twenty captions each sinusoiding
##     2px on their own phase offset is motion with no meaning.
##   * the SETTLE, a 0.955 -> 1.0 scale ramp on arrival. Scaling text off the
##     pixel grid is LAW 1's whole complaint about smooth type on pixel art.
##
## Everything the class KNOWS is kept, because none of it was the problem: the
## claim/ladder pass that stops two captions sharing pixels, the reserved boxes,
## the HUD-band dodge, the player-clearance rule, the priority-aware distance
## fade and the density pass. A quieter caption still has to be a placed one.
##
## The palette is now decided HERE rather than by forty call sites (LAW 2 and
## LAW 4): wayfinding — priority 3, the answer to "where do I go" — is drawn in
## the region ACCENT, and every other caption is TEXT_DIM. Builders still pass a
## colour; it is used for wayfinding and ignored for the rest, which is how ten
## regions stopped shipping four differently-hued gags each.

# Master palette (VISUAL_BIBLE_V2 LAW 2, the global constants).
const WHITE_HOT := Color("#F4F9FF")
const TEXT := Color("#D8DEEA")
const TEXT_DIM := Color("#7C8BB0")

## Above every world sprite (props top out near y_max + half ≈ 1050) and above
## the foreground framing (500–601). Deliberately below enemy HP bars (≈ +600
## on the enemy) and the player's own interact prompt, which must never be
## covered by set dressing. Kept at its round-5 value: other files reference it
## by name (region_portal.gd, projectile.gd, combat_fx.gd, npc.gd).
const Z_PLATE := 1150

## The furthest a caption is EVER allowed to sit from the thing it names, in
## world units. Past this radius the association is lost anyway: text 200 units
## from its prop is not "that prop's caption drawn over here", it is a caption
## sitting on whatever it landed next to. So the ladder stops here, and beyond it
## the label takes the least-bad overlap or gives up entirely.
const DISPLACE_MAX := 112.0

## Fraction of its own area a caption may overlap a claim it cannot evict before
## hiding is the better answer. A few clipped pixels is a smaller failure than a
## missing caption; a third of the text buried is not. Wayfinding (priority 3)
## gets twice the allowance, because its absence is a much bigger hole.
const OVERLAP_TOL := 0.16
const OVERLAP_TOL_HEAD := 0.34

## Candidate offsets, cheapest displacement first. Vertical nudges come before
## horizontal ones because a caption that slides sideways stops pointing at the
## thing it names. Every rung is within DISPLACE_MAX by construction — if you
## add one, keep it inside that radius or _place will silently skip it.
const LADDER := [
	Vector2(0, 0), Vector2(0, -26), Vector2(0, 26), Vector2(0, -52), Vector2(0, 52),
	Vector2(-84, 0), Vector2(84, 0), Vector2(0, -80), Vector2(0, 80),
	Vector2(-84, -46), Vector2(84, -46), Vector2(-84, 46), Vector2(84, 46),
	Vector2(0, -108), Vector2(0, 108), Vector2(-88, -64), Vector2(88, -64),
	Vector2(-88, 64), Vector2(88, 64), Vector2(-112, 0), Vector2(112, 0),
]

## Style presets, kept under their old key names so no caller changes.
## There is only one style of text now — the keys differ in whether the caption
## may be MOVED and whether it distance-fades.
##   plate    — a free-standing caption: claims a slot, dodges, fades.
##   headline — the same, at wayfinding weight (the builders pass priority 3).
##   tag      — text pinned ON a prop face (a monitor). Cannot slide off its art.
##   plaque   — printed matter that is part of the scenery. Never moves, never
##              distance-fades, keeps its authored z.
const STYLES := {
	"plate": {"pl": true, "bob": false, "fade": true, "claim": true, "bar": 0.0},
	"headline": {"pl": true, "bob": false, "fade": true, "claim": true, "bar": 0.0},
	"tag": {"pl": false, "bob": false, "fade": true, "claim": true, "bar": 0.0},
	"plaque": {"pl": false, "bob": false, "fade": false, "claim": false, "bar": 0.0},
}

## Air around the glyphs, for the claim box only. With no plate to pad there is
## nothing to draw here — it is the breathing room the ladder reserves so two
## captions cannot end up shoulder to shoulder.
const PAD := Vector2(6.0, 4.0)

## Reserved HUD bands, in viewport units against the 1080-unit design height.
## Read off scenes/ui/hud.tscn and hud.gd plus a few units of margin — these are
## the numbers to re-check if the HUD ever moves.
const BAND_TOP := 170.0
const BAND_BOTTOM := 114.0
const BAND_OBJECTIVE_W := 448.0
const BAND_OBJECTIVE_H := 264.0
const BAND_MINIMAP_W := 240.0
const BAND_MINIMAP_H := 238.0

## The furthest a caption will slide, in screen units, to get out of a band.
## Past this the move itself is more misleading than the overlap, so it fades.
## Measured off the round-5 production frame, where the bottom row of captions
## asks for ~124 units against a bottom band starting at 966.
const PUSH_MAX := 156.0

## Clear air a caption keeps from the left and right VIEWPORT edges. Text cut off
## by the side of the frame reads as the same clipping bug as text cut off by the
## bottom, and nothing else covers the sides.
const BAND_EDGE := 18.0

## Boss reserved band, added to the TOP band only while a boss is alive.
##
## ROUND 9: the whole boss layer now lives in the top announcement band —
## boss_hud.gd draws the name at y 222..256, a 4px health bar at y 262..266 and
## its phase call-outs at y 278..300, all of it inside the existing 372 above.
## BOSS_BAND_BOTTOM used to reserve 242px at the FOOT of the screen for the
## round-6 status plate, which was deleted with the plates; captions spent every
## boss fight dodging a lane nothing occupies. It is 0 rather than removed so the
## two bands stay a matched pair — if a boss element ever returns to the bottom
## of the frame, this is the number that reserves it.
const BOSS_BAND_TOP := 372.0
const BOSS_BAND_BOTTOM := 0.0

## The furthest the live dodge will ever carry a caption from its home, in world
## units. It has to be PUSH_MAX expressed in world units, or the two caps
## silently disagree and the smaller one wins: _hud_push measures and caps in
## CANVAS units, _retarget re-caps the same vector in WORLD units against this.
## The conversion is the camera's zoom, 1.5 (scenes/player/player.tscn), so
## 156 / 1.5 = 104. The zoom moved from 1.35 to 1.5 this round: LAW 1 wants one
## art pixel to be a whole number of screen pixels, and 2.0 sprite scale x 1.35
## is 2.7. At 1.5 it is exactly 3, and a 1280-wide region also fills a 1920
## viewport exactly instead of leaving void bars down both sides.
const DODGE_MAX := 104.0

## Where the player's own pixels are, relative to their global_position (which is
## at their FEET). MEASURED off the round-5 localhost frame: the character's ink
## runs world x 695..753, y 556..672 at a (720,640) spawn. The box is
## deliberately wider than that — a caption that stops one pixel from a shoulder
## still reads as touching it.
##
## A body is a BOX, not a point. The old test asked whether the player's position
## was inside the caption, and a caption hanging at chest height never contains
## the feet — which is how localhost's "talk to Claude first" sat across the
## character's head in every single frame.
const PLAYER_BODY := Rect2(-46.0, -84.0, 92.0, 118.0)
## Air the caption keeps around that body before it counts as an overlap...
const PLAYER_CLEAR := 18.0
## ...and the wider ring in which it merely dims out of the character's way.
const PLAYER_RING := 58.0

## Density. How many captions of AT LEAST this one's priority may be nearer to
## the player before this one is treated as crowded out, and the floor the
## crowding decay stops at. Wayfinding (priority 3) is exempt — it is the answer
## to "what do I do next" and is never the thing that gets quieter.
const CROWD_BUDGET := 3
const CROWD_DECAY := 0.76
const CROWD_MIN := 0.34

## How much of its own footprint a PINNED caption may have inside a reserved band
## before it gives up and fades. Measured on how much of the text is ACTUALLY
## inside a band, not on how far it is from the band's outside edge: every band
## carries a safety margin over the HUD it protects, and a caption grazing that
## margin by a unit is not worth losing.
const BOLT_CLIP := 0.12

## Distance fade. Near everything is full strength; past FADE_NEAR a caption dims
## toward its priority floor, and a low-priority caption is culled outright once
## it is further away than the player could plausibly be reading it.
const FADE_NEAR := 340.0
const FADE_FAR := 1180.0
## Length of the dissolve at the cull radius. A hard cut there reads as a bug.
const CULL_RAMP := 160.0
## Cull radius by priority. A caption you have walked away from is finished;
## wayfinding never culls, because the sign that says where to go has to be
## readable from where you are.
const CULL_BY_PRIO := [820.0, 820.0, 1420.0, 1.0e9]
## Ceiling by priority, so a static frame shows its own reading order.
const PEAK_BY_PRIO := [0.80, 0.80, 0.90, 1.0]

## Layout state for the region currently being built. Builds are strictly
## sequential (one region exists at a time), so static state is safe here and
## saves threading a layout object through forty call sites.
static var _claims: Array = []
static var _prios: Array = []
static var _owners: Array = []
static var _bounds := Rect2(0.0, 0.0, 1280.0, 960.0)
static var _box_cache: Dictionary = {}
static var _font_cache: Dictionary = {}

## Every label currently in the tree, for the density pass. Deliberately an
## untyped Array: `Array[WorldLabel]` inside the class that declares WorldLabel
## is exactly the kind of identifier this file has silently died on before
## (HANDOVER 6b). Entries are added in _ready, removed in _exit_tree, pruned in
## begin().
static var _live: Array = []
## Resolved once. Looked up by PATH and called by NAME rather than through the
## `UIManager` global, so a rename or a missing autoload degrades to "no modal is
## open" instead of killing every caption in the game.
static var _ui: Node = null
## Boss-band state, shared by every label and recomputed at most once per
## retarget interval.
static var _boss_on := false
static var _boss_ms := -10000

## The label's footprint in world space. Kept because callers read it (and
## because the claim system needs it); nothing hangs a fixture off it any more.
var box := Rect2()

var _home := Vector2.ZERO
var _size := Vector2.ZERO
var _center := Vector2.ZERO
var _t := 0.0
var _tick := 0.0
var _do_fade := true
var _alpha := 1.0
var _target := 1.0
var _floor := 0.34
var _cull := FADE_FAR
var _dodge := Vector2.ZERO
var _dodge_to := Vector2.ZERO
var _hud_hide := false
## Largest fraction of this label's footprint that any one reserved HUD band
## covers, recomputed with the push in _hud_push. See BOLT_CLIP.
var _hud_over := 0.0
var _player: Node2D = null
## Authoring priority, kept on the node so the density pass can rank captions
## against each other.
var _prio := 1
## Ceiling this label's alpha may reach, from PEAK_BY_PRIO.
var _peak := 1.0
## Distance from the player to this label's centre, refreshed each retarget so
## the density pass can read it off the neighbours. Starts effectively infinite
## so a label that has not had its first retarget is never counted as "nearer".
var _dist := 1.0e9
## Text that is PART OF THE ARTWORK it sits on (`tag` on a monitor face, `plaque`
## on a wall poster). The bezel is its frame; sliding it is worse than any
## overlap it could be sliding out of, so it yields with alpha alone.
var _pinned := false

# --------------------------------------------------------------- layout -----

## Call once at the top of a region build. `bounds` is the room rect; labels are
## clamped inside it, so a nudge can never push text into a wall or off-world.
static func begin(bounds: Rect2) -> void:
	_claims.clear()
	_prios.clear()
	_owners.clear()
	_bounds = bounds
	# The previous region's labels deregister themselves in _exit_tree, but a
	# region torn down with free() rather than queue_free() can leave a dangling
	# entry behind; the density pass must never walk one.
	var alive: Array = []
	for o in _live:
		if o != null and is_instance_valid(o):
			alive.append(o)
	_live = alive

## The room rect the current build is laying out inside, for the handful of
## nodes that draw their OWN text and therefore never pass through _clamp_in()
## — region_portal.gd's destination line is the one live case. Returning it
## beats each of those re-deriving the room size from its builder's constants.
static func bounds() -> Rect2:
	return _bounds

## Reserve a box drawn by somebody else — a portal's destination plate, an NPC's
## name tag, a monitor face with baked-in text. Reserved first, at max priority,
## so captions move out of THEIR way rather than the other way round.
static func reserve(rect: Rect2) -> void:
	_claims.append(rect)
	_prios.append(99)
	_owners.append(null)

## Text size measured from the real font, not guessed from character counts.
static func measure(text: String, font_size: int) -> Vector2:
	var key := "%d|%s" % [font_size, text]
	if _box_cache.has(key):
		return _box_cache[key]
	var size := Vector2.ZERO
	var font: Font = _face()
	if font:
		size = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	if size.x < 2.0:
		var lines := text.split("\n")
		var widest := 0
		for l in lines:
			widest = maxi(widest, l.length())
		size = Vector2(float(widest) * float(font_size) * 0.62, float(lines.size()) * float(font_size) * 1.35)
	_box_cache[key] = size
	return size

## The aliased face, LAW 1. Smooth vector text over 2x pixel art is one of the
## five pixel sizes the brief counted in a single frame, and it is the one this
## file owns. `FontFile` carries the three switches that matter, so the default
## font is duplicated and switched off at the source.
##
## Deliberately duplicated from game_theme.ui_font() rather than called: a
## compile-time dependency on another class is how this file died once already
## (HANDOVER 6b), and a parse error HERE deletes every caption in the game while
## all 28 suites still pass. Six lines is cheaper than that risk. If the base
## font is not a FontFile the theme's own face is used unchanged, which is the
## known-good pre-round-7 behaviour.
static func _face() -> Font:
	if _font_cache.has("aliased"):
		return _font_cache["aliased"]
	var base: Font = ThemeDB.fallback_font
	var out: Font = base
	if base is FontFile:
		var f: FontFile = (base as FontFile).duplicate()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.multichannel_signed_distance_field = false
		# Prove the duplicate can still set type before anything is drawn with it.
		# A Resource.duplicate() that did not carry the glyph data would render
		# every caption in the game as nothing, and it would do so silently — the
		# suites would still pass. One measurement is a cheap insurance premium.
		if f.get_string_size("Ag", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x > 1.0:
			out = f
	_font_cache["aliased"] = out
	return out

## Three world text sizes, not eleven. LAW 1 asks for a small fixed ladder; the
## builders authored 10, 11, 12 and 13 across ten regions, which at the region
## zoom is four different text heights in one frame for no reason a player could
## name.
static func _snap_size(want: int) -> int:
	if want <= 10:
		return 10
	if want <= 12:
		return 12
	return 14

# ----------------------------------------------------------- construction ---

## Build a world label. Returns the node (already parented) — hidden rather than
## overlapping when the room has no space left and this label is expendable.
##
## opts: size (int font size), style (see STYLES), priority (int, higher wins a
## contested spot), z (int z_index override), color (text colour override),
## plate/bob/fade/claim/bar (per-call overrides, kept so no caller breaks; the
## plate and bar are gone and those two are now only read as "is this pinned").
static func add(parent: Node2D, pos: Vector2, text: String, accent: Color, opts: Dictionary = {}) -> WorldLabel:
	var style_name := str(opts.get("style", "plate"))
	var style: Dictionary = STYLES.get(style_name, STYLES["plate"])
	var font_size := _snap_size(int(opts.get("size", 12)))
	var free_standing := bool(opts.get("plate", style["pl"]))
	var want_fade := bool(opts.get("fade", style["fade"]))
	var want_claim := bool(opts.get("claim", style["claim"]))
	var prio := int(opts.get("priority", 1))
	var z := int(opts.get("z", Z_PLATE))

	# LAW 2 and LAW 4 decide the colour, not the caller. Wayfinding — the caption
	# that answers "where do I go" — is the region ACCENT, lifted until it clears
	# a readability floor. Everything else is TEXT_DIM, so a room full of captions
	# has ONE hue in it and an obvious reading order. An explicit `color` still
	# wins, because a monitor readout is part of its screen's artwork.
	var text_col: Color = _readable(accent) if prio >= 3 else TEXT_DIM
	if opts.has("color"):
		text_col = opts["color"]

	var label := _text_node(text, font_size, text_col)
	var text_size := label.size
	var box_size := text_size + PAD * 2.0
	var placed := _place(pos, box_size, prio, want_claim)
	var at: Vector2 = placed["pos"]
	# LAW 1: static world objects sit on even integers. Text on a half-pixel is
	# the same smearing as text at 2.2x scale.
	at = Vector2(round(at.x * 0.5) * 2.0, round(at.y * 0.5) * 2.0)

	var node := WorldLabel.new()
	node.name = "WorldLabel"
	node.position = at
	node.z_index = z
	node.box = Rect2(at, box_size)
	node._home = at
	node._size = box_size
	node._center = at + box_size * 0.5
	node._do_fade = want_fade
	node._floor = 0.18 if prio <= 1 else (0.46 if prio >= 3 else 0.32)
	node._prio = prio
	var tier := clampi(prio, 0, 3)
	node._cull = float(CULL_BY_PRIO[tier])
	node._peak = float(PEAK_BY_PRIO[tier])
	node._pinned = not free_standing
	# Modals and dialogues either pause the tree or hold it while a panel covers
	# the lower third. A caption frozen at full alpha behind a semi-transparent
	# panel is the bleed-through defect; one that keeps ANIMATING under it is
	# HANDOVER 4.4. So: always processing, and _retarget's first act is to notice
	# the modal and go quiet. Nothing here tweens, so nothing can freeze half-way.
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	var slot := int(placed["slot"])
	if slot >= 0 and slot < _owners.size():
		_owners[slot] = node
	parent.add_child(node)

	label.position = PAD
	node.add_child(label)

	if not bool(placed["ok"]):
		# The room genuinely ran out of clear space and this label is expendable.
		# Silence beats two captions sharing pixels.
		node.visible = false
		node.set_process(false)
	return node

## One block of world text: aliased glyphs and a 1px black drop shadow at 80%,
## offset (1,1). That is the entire treatment (LAW 4).
##
## The outline is gone with the plate. A 3-5px outline is a second silhouette
## around every glyph — it thickens the type, it fringes under bloom, and it was
## there to hold text against a BRIGHT floor. The floors are quiet now, so the
## shadow alone does the separating, which is what a shadow is for.
static func _text_node(text: String, font_size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	var face := _face()
	if face:
		lbl.add_theme_font_override("font", face)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.add_theme_constant_override("line_spacing", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	# Measured from the font, not from the Label: a Control that is not yet in the
	# tree has no resolved theme cache, so its own minimum size can come back as
	# zero. Whichever number is bigger wins, plus a couple of pixels for bearing.
	var m := measure(text, font_size)
	lbl.reset_size()
	lbl.size = Vector2(maxf(m.x, lbl.size.x) + 3.0, maxf(m.y, lbl.size.y) + 2.0)
	return lbl

# ------------------------------------------------------------- internals ----

## Region accents are authored for neon, not for reading. ACID #A8FF3E and GOLD
## #FFD34D are fine; ember #FF6B2D, heat #FF3D2D, VIOLET #8B5CF6 and corporate
## #4D7CFF are mud at 12px. Wayfinding colour is lifted toward WHITE_HOT until it
## clears a readability floor, keeping the hue but not the murk.
static func _readable(c: Color) -> Color:
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	if lum >= 0.70:
		return c
	return c.lerp(WHITE_HOT, clampf((0.70 - lum) * 1.5, 0.0, 0.72))

## Walk the ladder for a box that touches nothing already claimed and sits fully
## inside the room. Returns {"pos": Vector2, "ok": bool, "slot": int}; ok=false
## means the caller hides the label rather than printing two captions on the same
## pixels.
##
## Three tiers, in order, and every one of them respects DISPLACE_MAX:
##   1. a clear slot within the cap,
##   2. the home slot, evicting strictly lower-priority captions — wayfinding
##      beats a caption for the spot it actually belongs in,
##   3. the least-bad overlap within the cap, and only then silence.
## Displacement is measured from the CLAMPED HOME, not from the authored point:
## the clamp that pulls a wall-hugging caption into the room is not a
## displacement the ladder chose, and counting it against the cap disabled the
## ladder entirely for those captions.
static func _place(pos: Vector2, size: Vector2, prio: int, claim: bool) -> Dictionary:
	if not claim:
		return {"pos": pos, "ok": true, "slot": -1}
	var home := _clamp_in(pos, size)
	for off: Vector2 in LADDER:
		var at := _clamp_in(pos + off, size)
		if (at - home).length() > DISPLACE_MAX:
			continue
		if _colliders(Rect2(at, size)).is_empty():
			return {"pos": at, "ok": true, "slot": _claim(Rect2(at, size), prio)}
	# Nothing clear anywhere on the ladder. Wayfinding outranks flavour: evict
	# the losers from the home spot and take it.
	var hit := _colliders(Rect2(home, size))
	var defended := false
	for i: int in hit:
		if int(_prios[i]) >= prio:
			defended = true
			break
	if defended:
		return _least_bad(pos, size, prio)
	hit.reverse()
	for i: int in hit:
		var owner_node = _owners[i]
		if owner_node != null and is_instance_valid(owner_node):
			owner_node.visible = false
			owner_node.set_process(false)
		_claims.remove_at(i)
		_prios.remove_at(i)
		_owners.remove_at(i)
	return {"pos": home, "ok": true, "slot": _claim(Rect2(home, size), prio)}

## Tier 3. Every in-cap slot collides with a claim this label may not evict, so
## pick the one that overlaps the LEAST and accept the clip — provided the clip
## stays under this caption's share of its own area. Silence is the right answer
## to a full room; it is the wrong answer to a room where the caption would have
## fitted with six pixels of its shadow clipped.
static func _least_bad(pos: Vector2, size: Vector2, prio: int) -> Dictionary:
	var area := maxf(1.0, size.x * size.y)
	var tol := OVERLAP_TOL_HEAD if prio >= 3 else OVERLAP_TOL
	var home := _clamp_in(pos, size)
	var best := home
	var best_over := -1.0
	var best_cost := 0.0
	for off: Vector2 in LADDER:
		var at := _clamp_in(pos + off, size)
		if (at - home).length() > DISPLACE_MAX:
			continue
		var over := _overlap_area(Rect2(at, size), prio)
		var cost := over + (at - home).length() * 0.4
		if best_over < 0.0 or cost < best_cost:
			best_over = over
			best_cost = cost
			best = at
	if best_over < 0.0 or best_over > area * tol:
		return {"pos": home, "ok": false, "slot": -1}
	# Anything this label OUTRANKS that is still touching the slot it settled on
	# gets evicted, exactly as tier 2 would have done at home. Descending indices:
	# removing from the front would shift the rest.
	var loser := _colliders(Rect2(best, size))
	loser.reverse()
	for i: int in loser:
		if int(_prios[i]) >= prio:
			continue
		var owner_node = _owners[i]
		if owner_node != null and is_instance_valid(owner_node):
			owner_node.visible = false
			owner_node.set_process(false)
		_claims.remove_at(i)
		_prios.remove_at(i)
		_owners.remove_at(i)
	return {"pos": best, "ok": true, "slot": _claim(Rect2(best, size), prio)}

## Total area this box would bury of claims at or above `prio`. Raw intersection,
## not the grown test _colliders uses: near-misses are what tier 3 is looking
## for, so counting their breathing room as overlap would reject them all.
static func _overlap_area(r: Rect2, prio: int) -> float:
	var out := 0.0
	for i in _claims.size():
		if int(_prios[i]) < prio:
			continue
		var hit: Rect2 = (_claims[i] as Rect2).intersection(r)
		out += hit.size.x * hit.size.y
	return out

static func _claim(r: Rect2, prio: int) -> int:
	_claims.append(r)
	_prios.append(prio)
	_owners.append(null)
	return _claims.size() - 1

## Indices of every claim this box would touch. 6px of air around each: boxes
## that merely kiss still read as one smeared block at 1080p.
static func _colliders(r: Rect2) -> Array:
	var out: Array = []
	var grown := r.grow(6.0)
	for i in _claims.size():
		if (_claims[i] as Rect2).intersects(grown):
			out.append(i)
	return out

## The bottom of a room is where the camera stops following and where the whole
## of the HUD lives, so a caption authored down there spends its life inside the
## ability-bar band asking for a screen-space rescue. Build-time headroom is
## cheaper than a permanent runtime push.
##
## EDGE_KEEP is the floor under every one of those margins (round-8 critique #9,
## "a label clipped by the room edge"): whatever else this function is asked to
## reserve, no caption is ever placed with any part of it — including the pixel
## its drop shadow occupies — nearer than 24 units to the room's own bounds. The
## top keeps its larger value because the HUD band lives there, not because the
## wall does.
const EDGE_KEEP := 24.0

static func _clamp_in(at: Vector2, size: Vector2) -> Vector2:
	var lo := _bounds.position + Vector2(maxf(26.0, EDGE_KEEP), maxf(78.0, EDGE_KEEP))
	var hi := _bounds.position + _bounds.size - size - Vector2(maxf(26.0, EDGE_KEEP), maxf(60.0, EDGE_KEEP))
	return Vector2(clampf(at.x, lo.x, maxf(lo.x, hi.x)), clampf(at.y, lo.y, maxf(lo.y, hi.y)))

# --------------------------------------------------------------- runtime ----

func _ready() -> void:
	modulate.a = _alpha
	if not _live.has(self):
		_live.append(self)

func _exit_tree() -> void:
	_live.erase(self)

## Dodge and fade. Nothing else — no bob, no settle, no scale (LAW 9: text does
## not move at rest). The alpha and dodge targets are recomputed at ~8Hz;
## everything per-frame is a handful of floats and no allocations.
func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.12
		_retarget()
	if _dodge != _dodge_to:
		_dodge = _dodge.move_toward(_dodge_to, delta * 210.0)
		# Even integers, still, while it slides: half-pixel text smears.
		position = Vector2(
			round((_home.x + _dodge.x) * 0.5) * 2.0,
			round((_home.y + _dodge.y) * 0.5) * 2.0)
	if not is_equal_approx(_alpha, _target):
		_alpha = move_toward(_alpha, _target, delta * 2.4)
		modulate.a = _alpha

func _retarget() -> void:
	# A dialogue or a modal owns the screen. World captions are set dressing
	# BEHIND that panel, and every panel in this game is semi-transparent, so they
	# do not disappear — they show through as ghost text competing with the line
	# the player is actually reading. Fade out and stop measuring; everything
	# comes back when the panel closes.
	if _blocked():
		_target = 0.0
		return
	_measure_player()
	var push := _hud_push()
	if _pinned:
		# Cannot move: a tag is part of the monitor face it sits on and a plaque is
		# part of the poster. Both yield the only way they can, by fading. The
		# small dead zone matters — hiding on a two-pixel graze makes a caption
		# strobe as the player walks along a band boundary. _hud_push has already
		# raised _hud_hide where no move would have helped; never clear it.
		_dodge_to = Vector2.ZERO
		if not _hud_hide:
			_hud_hide = push.length() > 10.0 and _hud_over > BOLT_CLIP
	else:
		_dodge_to = push
		if _dodge_to.length() > DODGE_MAX:
			_dodge_to = _dodge_to.normalized() * DODGE_MAX
	var vis := _peak
	if _hud_hide:
		vis = 0.0
	elif _do_fade:
		# The three terms COMPETE, they do not compound. Each carries its own
		# stated floor, and those floors exist because "quieter than its
		# neighbours" and "invisible" are different states. Multiplying threw both
		# away: a furniture caption across the room with five nearer captions
		# landed at 0.155, which is a smudge. Taking the smallest term keeps the
		# reading order the density pass was written for.
		vis = minf(_peak, minf(_by_distance(), _crowd()))
	# Last, and after the HUD dodge is known, because this pass adds to it: the
	# character is the one thing on screen no caption may ever share pixels with.
	if vis > 0.0:
		vis = _clear_of_player(vis)
	_target = vis

## Is a dialogue or a full-screen panel up? Resolved by PATH and called by NAME:
## a hard `UIManager.has_blocking_ui()` would be a compile-time dependency of the
## one class whose death takes every caption in the game with it (HANDOVER 6b).
## Missing autoload or renamed method degrades to "nothing is blocking".
func _blocked() -> bool:
	if not is_instance_valid(_ui):
		_ui = get_node_or_null("/root/UIManager")
	if not is_instance_valid(_ui) or not _ui.has_method("has_blocking_ui"):
		return false
	return bool(_ui.call("has_blocking_ui"))

## Refresh `_player` and `_dist` once per retarget. Both the distance fade and
## the density pass need them, and the density pass reads `_dist` off the
## NEIGHBOURS — so it has to be a stored field, not a local.
func _measure_player() -> void:
	if not is_instance_valid(_player):
		var tree := get_tree()
		if tree == null:
			return
		_player = tree.get_first_node_in_group("player") as Node2D
	if is_instance_valid(_player):
		_dist = _player.global_position.distance_to(_center)

## Density. Fourteen captions in one apartment is not fourteen pieces of
## information, it is a wall of text with no reading order. Each caption asks how
## many captions of AT LEAST its own weight are nearer to the player than it is;
## past the budget it decays toward CROWD_MIN — still there, still legible up
## close, no longer competing. Wayfinding is exempt.
func _crowd() -> float:
	if _prio >= 3 or _live.size() <= CROWD_BUDGET:
		return 1.0
	var nearer := 0
	for o in _live:
		# Validity BEFORE the cast: casting a freed instance is not a safe way to
		# find out that it was freed.
		if o == null or not is_instance_valid(o):
			continue
		var other := o as WorldLabel
		if other == null or other == self:
			continue
		if not other.visible or other._prio < _prio:
			continue
		if other._dist < _dist:
			nearer += 1
	if nearer < CROWD_BUDGET:
		return 1.0
	return maxf(CROWD_MIN, pow(CROWD_DECAY, float(nearer - CROWD_BUDGET + 1)))

## Priority-aware distance fade. The floor is the point: wayfinding stays legible
## from across the room while a caption drops to a whisper, so a static frame
## shows its own reading order instead of twenty equal blocks of text.
func _by_distance() -> float:
	if not is_instance_valid(_player):
		return 1.0
	var d := _dist
	if d < FADE_NEAR:
		return 1.0
	var a := clampf(1.0 - (d - FADE_NEAR) / 700.0, _floor, 1.0)
	# The cull used to be a step: at _cull - 1 the caption held its floor and at
	# _cull + 1 it was gone. A player pacing across that radius made every caption
	# blink. Ramp the last stretch out instead.
	if d > _cull - CULL_RAMP:
		a *= clampf((_cull - d) / CULL_RAMP, 0.0, 1.0)
	return a

## No caption may share pixels with the character. Set dressing yields to the
## player and to the interact prompt over their head, always — first by MOVING,
## and only where it cannot move, by getting out of the frame entirely.
##
## Both rects are taken from the label's HOME and from the dodge TARGET, never
## from where the text currently sits. Testing the live position against the
## player is a feedback loop: the caption slides clear, the player is no longer
## inside it, the dodge releases, it slides back in, forever.
func _clear_of_player(vis: float) -> float:
	if not is_instance_valid(_player):
		return vis
	# Home in global space (`_home` is parent-local and the live `position`
	# carries the dodge), plus the slide the HUD pass has already asked for.
	var ghome := global_position - (position - _home)
	var r := Rect2(ghome + _dodge_to, _size)
	var body := Rect2(_player.global_position + PLAYER_BODY.position, PLAYER_BODY.size)
	if not r.grow(PLAYER_CLEAR + PLAYER_RING).intersects(body):
		return vis
	if not r.grow(PLAYER_CLEAR).intersects(body):
		return minf(vis, 0.62)
	if _pinned:
		return 0.0                          # cannot slide (see _pinned)
	# Shortest slide that takes the whole caption — plus its clearance — off the
	# whole body, rather than a nudge that only clears the feet.
	var keep := r.grow(PLAYER_CLEAR)
	var d := body.get_center() - keep.get_center()
	var ex := (keep.size.x + body.size.x) * 0.5 - absf(d.x)
	var ey := (keep.size.y + body.size.y) * 0.5 - absf(d.y)
	var slide := Vector2.ZERO
	if ey <= ex:
		# A dead-centre hit has no sign to take, so it defaults to lifting the
		# caption clear rather than dropping it onto the character's feet.
		slide = Vector2(0.0, ey * (-1.0 if d.y >= 0.0 else 1.0))
	else:
		slide = Vector2(ex * (-1.0 if d.x >= 0.0 else 1.0), 0.0)
	var want := _dodge_to + slide
	if want.length() > DODGE_MAX:
		want = want.normalized() * DODGE_MAX
	_dodge_to = want
	# Did the capped slide actually get clear? If the HUD push and the player were
	# pulling in different directions there may be nothing left to spend, and a
	# caption still on the character at the end of its travel has to fade instead
	# of pretending the move worked.
	if Rect2(ghome + _dodge_to, _size).grow(PLAYER_CLEAR).intersects(body):
		return 0.0
	# It is on its way out. Dim while it travels, so the handover reads as the
	# caption stepping aside.
	return minf(vis, 0.55)

## This label's footprint in SCREEN space, taken from its HOME rather than from
## wherever the dodge currently has it — testing the dodged rect against the
## bands is a feedback loop. get_global_transform_with_canvas() is the ONLY
## transform that includes the camera.
func _home_screen_rect(sc: Vector2) -> Rect2:
	var xf := get_global_transform_with_canvas()
	# WorldLabel extends Node2D — there is no `size`. `box` is the real footprint
	# in world space, set at placement time.
	var plate: Vector2 = box.size if box.size != Vector2.ZERO else Vector2(180.0, 40.0)
	var origin := xf.origin - (position - _home) * sc
	return Rect2(origin, plate * sc)

## How far this caption has to move, in WORLD units, to get clear of the HUD's
## reserved bands — and sets `_hud_hide` when no move short enough exists.
##
## Hiding is the wrong FIRST answer: the caption drifting into a band is usually
## the one you just walked up to read. It slides out, and only gives up when
## clearing it would cost more than PUSH_MAX or when the band has no free side.
##
## Bands: the top bar (resources / region banner / cycle readout / toast lane),
## the bottom ability bar + controls footer, the bottom-left objective panel and
## the bottom-right minimap. Each is max(absolute, fraction-of-viewport) so an
## unusual window aspect cannot shrink a band below the HUD it protects.
func _hud_push() -> Vector2:
	_hud_hide = false
	_hud_over = 0.0
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var view: Vector2 = vp.get_visible_rect().size
	if view.x < 1.0 or view.y < 1.0:
		return Vector2.ZERO
	var sc := get_global_transform_with_canvas().get_scale()
	if sc.x < 0.0001 or sc.y < 0.0001:
		return Vector2.ZERO
	var r := _home_screen_rect(sc)
	# Fully off-screen: not a HUD problem, let the distance fade decide.
	if not r.intersects(Rect2(Vector2.ZERO, view)):
		return Vector2.ZERO
	var top := maxf(BAND_TOP, view.y * 0.157)
	var bottom_pad := maxf(BAND_BOTTOM, view.y * 0.105)
	# A boss owns two more bands while it is alive. boss_hud.gd braces both with
	# opaque plates, but an opaque plate only stops a caption being READ THROUGH.
	# Not being covered is the boss HUD's job; not being THERE is this one's.
	if _boss_active():
		top = maxf(top, BOSS_BAND_TOP)
		bottom_pad = maxf(bottom_pad, BOSS_BAND_BOTTOM)
	var bottom := view.y - bottom_pad
	var down := maxf(0.0, top - r.position.y)
	var up := maxf(0.0, r.end.y - bottom)
	if down > 0.0 and up > 0.0:
		# Taller than the gap between the two bars: it is in both, whichever way
		# it goes. Nothing to measure — it is buried by definition.
		_hud_hide = true
		_hud_over = 1.0
		return Vector2.ZERO
	var push := Vector2(0.0, down - up)
	# The two bottom corner panels: leaving sideways is usually the shorter trip,
	# so take whichever of "outward" and "up" costs less. Each branch KEEPS the
	# vertical clearance the bar bands already asked for — overwriting it meant a
	# caption took the sideways exit out of the objective panel and parked itself
	# under the ability bar instead.
	var obj_w := maxf(BAND_OBJECTIVE_W, view.x * 0.200)
	var obj_top := view.y - maxf(BAND_OBJECTIVE_H, view.y * 0.244)
	if r.position.x < obj_w and r.end.y > obj_top:
		var side := obj_w - r.position.x
		var lift := r.end.y - obj_top
		push = Vector2(side, push.y) if side <= lift else Vector2(push.x, -lift)
	var map_x := view.x - maxf(BAND_MINIMAP_W, view.x * 0.107)
	var map_top := view.y - maxf(BAND_MINIMAP_H, view.y * 0.220)
	if r.end.x > map_x and r.end.y > map_top:
		var side2 := r.end.x - map_x
		var lift2 := r.end.y - map_top
		push = Vector2(-side2, push.y) if side2 <= lift2 else Vector2(push.x, -lift2)
	# The side edges of the FRAME itself. The two bar bands already run to the top
	# and bottom edges; nothing covered the sides, and half a caption hanging off
	# the left of the frame reads as the same clipping bug. Applied as a
	# floor/ceiling rather than added, so it cannot compound with the corner
	# panels.
	var out_l := maxf(0.0, BAND_EDGE - r.position.x)
	var out_r := maxf(0.0, r.end.x - (view.x - BAND_EDGE))
	if out_l > 0.0 and out_r > 0.0:
		# Wider than the frame: there is no sideways move that helps.
		_hud_hide = true
		_hud_over = 1.0
		return Vector2.ZERO
	if out_l > 0.0:
		push.x = maxf(push.x, out_l)
	elif out_r > 0.0:
		push.x = minf(push.x, -out_r)
	# How much of the text is really inside a band, as a fraction of its own area.
	# Worst single band, not the union: summing would double-count the corner
	# panels against the bar band they sit inside.
	_hud_over = maxf(
		maxf(_clip_frac(r, Rect2(0.0, 0.0, view.x, top)),
			_clip_frac(r, Rect2(0.0, bottom, view.x, view.y - bottom))),
		maxf(_clip_frac(r, Rect2(0.0, obj_top, obj_w, view.y - obj_top)),
			_clip_frac(r, Rect2(map_x, map_top, view.x - map_x, view.y - map_top))))
	# The off-frame strips count too, so a PINNED caption sliced by the side of
	# the frame fades rather than sitting there as half a word.
	_hud_over = maxf(_hud_over, maxf(
		_clip_frac(r, Rect2(-view.x, 0.0, view.x + BAND_EDGE, view.y)),
		_clip_frac(r, Rect2(view.x - BAND_EDGE, 0.0, view.x + BAND_EDGE, view.y))))
	if push.length() > PUSH_MAX:
		# Give up on clearing the band, but keep the slide we DO have instead of
		# snapping home. Returning ZERO here made the caption travel back INTO the
		# HUD over the ~0.3s the fade takes, so the last thing the player saw was
		# it walking under the ability bar. Hold at the cap and fade.
		_hud_hide = true
		push = push.normalized() * PUSH_MAX
	return Vector2(push.x / sc.x, push.y / sc.y)

## Is a boss on the field? Shared across every label and recomputed at most once
## per retarget interval, because twenty captions each walking the enemy group at
## 8Hz is twenty times the scanning the answer is worth.
##
## Asked of the ENEMY, not of the HUD: `BossHud` is a CanvasLayer parented to the
## boss and detached into the scene for the death sequence, so its path is not
## stable, whereas the "enemy" group and enemy_base.gd's exported `is_boss` are
## both public and have been for the life of the project. `get()` on a Node that
## does not carry the property returns null rather than erroring, and null is
## read here as "not a boss" — this class does not get to die of a typo again.
func _boss_active() -> bool:
	var now := Time.get_ticks_msec()
	if now - _boss_ms < 110:
		return _boss_on
	_boss_ms = now
	_boss_on = false
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group("enemy"):
		var e := n as Node
		if e == null or not is_instance_valid(e):
			continue
		var flag = e.get("is_boss")
		if flag is bool and flag:
			_boss_on = true
			break
	return _boss_on

## Fraction of `r` that `band` covers. Rect2.intersection returns a zero-size
## rect when they miss, so the no-overlap case falls out for free.
static func _clip_frac(r: Rect2, band: Rect2) -> float:
	var a := r.size.x * r.size.y
	if a <= 0.0:
		return 0.0
	var i := r.intersection(band)
	return (i.size.x * i.size.y) / a
