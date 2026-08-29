extends Node2D
class_name WorldLabel
## The ONE way world text is drawn. Both builders route every sign, caption,
## plaque and screen readout through here.
##
## Why this exists: world text used to be a raw Label at z_index 400, which is
## BELOW most of the world. Props y-sort themselves to `int(y + half_height)` —
## a crate at y=620 draws at z ~660, a bed at y=840 draws at z ~894 — so every
## caption in the lower two thirds of every room was painted over by its own
## scenery. Captured frames showed exactly that: "Egress f… to leavi… nking.",
## "npm install (attempt #4…", "PIZZA ARCH…OLOGY". Nothing was clipping; the
## props were simply in front of the text.
##
## A world label now gets:
##   * a z_index above every world sprite (Z_PLATE), below combat readouts,
##   * a dark glass plate + hairline border + accent bar, so it reads on ANY
##     background instead of hoping the background stays dark,
##   * automatic sizing measured from the real font — it cannot clip,
##   * a claim/ladder pass so two labels never share pixels; the loser is
##     nudged, and if the room is genuinely full the lower-priority one hides,
##   * a hard cap on how far the ladder may carry it from its subject, and a
##     short elbow tick — never a full-length line — when it did move,
##   * a TITLE / SUBTITLE typographic split WHERE the first line is a name —
##     tracked, brighter, outlined title over a dimmer, one-step-smaller
##     subtitle, divided by a hairline rule; prose captions stay one block,
##   * distance fade with a priority-aware floor (a wayfinding caption stays
##     legible across the room; a gag dims out of the way first),
##   * a live dodge: when the player walks into a caption, or the caption drifts
##     into a reserved HUD band, it slides clear (and ducks) instead of sitting
##     on the character's head or printing through the cycle readout,
##   * an appear/settle on approach, and a gentle float phase-offset per label
##     so they never bob in unison.
##
## Round 5 note on the HUD bands, because the old ones had a hole in them. The
## top band was 104 units tall in a 1080-unit canvas; the HUD's TopBar ends at
## 86, the cycle chip runs to ~121 and the notification lane occupies 120..148.
## A caption whose plate started at 105 therefore cleared the test and landed
## squarely on the cycle readout — which is exactly what the
## corporate_enterprise QA frame shows, "OPEN PLAN" printed through "Cycle 1 ·
## reset in 139s". The bands are now measured off the real HUD scene rects with
## a margin, expressed as max(absolute, fraction-of-viewport) so a different
## window aspect cannot shrink them, and a caption that lands in one SLIDES OUT
## before it is allowed to give up and fade.
##
## Round 6, the placement pass. Five things a caption is now categorically not
## allowed to do, each of them a defect somebody could point at in a frame:
##
##   1. Share pixels with the CHARACTER. The player is a box, not a point — see
##      PLAYER_BODY and _clear_of_player. This is the whole of "talk to Claude
##      first ->" drawn through the player's head in every localhost frame.
##   2. Be sliced by the frame EDGE. The bars covered the top and bottom edges;
##      the sides were open (BAND_EDGE), and PUSH_MAX was six units short of what
##      the bottom row of captions actually asks for, so they hid instead of
##      sliding and the fade left half-glyph text at the edge on the way out.
##   3. Sit in a BOSS band. boss_hud.gd braces its own plates so nothing is read
##      THROUGH them; not being there in the first place is this file's half of
##      that contract (BOSS_BAND_TOP / BOSS_BAND_BOTTOM, gated on _boss_active).
##   4. Show through a MODAL. Dialogue and the panels are semi-transparent, so a
##      caption behind one is ghost text competing with the line being read.
##      Labels are PROCESS_MODE_ALWAYS and fade on _blocked().
##   5. Arrive fourteen at a time. Priority-and-distance density (_crowd,
##      CULL_BY_PRIO, PEAK_BY_PRIO) gives a static frame a reading order.
##
## Where a caption cannot satisfy these by MOVING — a bolted headline, a caption
## pinned to the artwork it labels — it fades. Silence is a legible state; a
## caption drawn badly is not.

# Master palette (docs/VISUAL_BIBLE.md).
const PLATE_BG := Color("#0B0E1C")
const PLATE_LINE := Color("#2A3558")
const WHITE_HOT := Color("#F4F9FF")
const TEXT_DIM := Color("#7C8BB0")

## Above every world sprite (props top out near y_max + half ≈ 1050) and above
## the foreground framing (500–601). Deliberately below enemy HP bars (≈ +600
## on the enemy) and the player's own interact prompt, which must never be
## covered by set dressing.
const Z_PLATE := 1150

## The furthest a caption is EVER allowed to sit from the thing it names, in
## world units. This is the anti-beam rule and it is not negotiable.
##
## Round 5 shipped a ladder that reached 208 units sideways and 152 up, and drew
## a full-length line from the displaced plate back to its subject. A caption
## authored outside the room rect got worse: `_clamp_in` dragged it hundreds of
## units and the leader followed, so the annotation for a 12px caption was a
## 300-unit ray across the play area. Under HDR bloom at region-accent hue that
## does not read as typography, it reads as a laser or as a rendering fault —
## and the vault and mines frames are already full of real lasers and heat
## beams for it to be confused with.
##
## Past this radius the association is lost anyway: a plate 200 units from its
## prop is not "that prop's caption drawn over here", it is a caption sitting on
## whatever it landed next to. So the ladder stops here, and beyond it the label
## takes the least-bad overlap or gives up entirely (see _place / _least_bad).
const DISPLACE_MAX := 112.0

## Fraction of its own area a caption may overlap a claim it cannot evict before
## hiding is the better answer. A few pixels of a neighbour's shadow clipped is a
## smaller failure than a missing caption; a third of the text buried is not.
##
## A region name (priority 3) gets twice the allowance, because its absence is a
## much bigger hole than a gag's — and because a headline that hides also takes
## its neon tube, brackets and floor pool with it (region_builder._sign bails on
## `not lbl.visible`), leaving a lit fixture with nothing under it. Laying the
## ten regions out with these numbers, every clip that tier 3 actually accepts
## lands on a RESERVED box — an NPC's bark column, a portal's destination plate —
## and none of them lands on another caption.
const OVERLAP_TOL := 0.16
const OVERLAP_TOL_HEAD := 0.34

## Candidate offsets, cheapest displacement first. Vertical nudges come before
## horizontal ones because a sign that slides sideways stops pointing at the
## thing it names. Every rung is within DISPLACE_MAX by construction — if you
## add one, keep it inside that radius or _place will silently skip it.
const LADDER := [
	Vector2(0, 0), Vector2(0, -26), Vector2(0, 26), Vector2(0, -52), Vector2(0, 52),
	Vector2(-84, 0), Vector2(84, 0), Vector2(0, -80), Vector2(0, 80),
	Vector2(-84, -46), Vector2(84, -46), Vector2(-84, 46), Vector2(84, 46),
	Vector2(0, -108), Vector2(0, 108), Vector2(-88, -64), Vector2(88, -64),
	Vector2(-88, 64), Vector2(88, 64), Vector2(-112, 0), Vector2(112, 0),
]

## Style presets (key names deliberately avoid GDScript type keywords).
##   plate    — the default sign: glass plate, accent bar, float, distance fade.
##   headline — a plate with a heavier accent bar and an underlit base, for the
##              one or two signs per region that name the whole place.
##   tag      — outlined text only, authored z, for readouts that live ON a prop
##              face (monitors), where a plate would cover the screen art.
##   plaque   — outlined text only, no float, no fade, authored z. For printed
##              matter that is part of the scenery (wall posters).
const STYLES := {
	"plate": {"pl": true, "bob": true, "fade": true, "claim": true, "bar": 3.0},
	"headline": {"pl": true, "bob": true, "fade": true, "claim": true, "bar": 5.0},
	"tag": {"pl": false, "bob": false, "fade": true, "claim": true, "bar": 0.0},
	"plaque": {"pl": false, "bob": false, "fade": false, "claim": false, "bar": 0.0},
}

const PAD := Vector2(9.0, 5.0)

## Gap between the title line and the subtitle block, and the hairline rule that
## sits in the middle of it on plated styles.
const TITLE_GAP := 5.0

## Reserved HUD bands, in viewport units against the 1080-unit design height.
## Read off scenes/ui/hud.tscn and the runtime layout constants in hud.gd, plus
## a few units of margin each — these are the numbers to re-check if the HUD
## ever moves:
##   TopBar        14..86        cycle chip ~90..121
##   toast lane    TOAST_TOP 100 .. +TOAST_H 66  ->  100..166
##   ability row   ABILITY_BAR_TOP -100 .. ABILITY_BAR_BOTTOM -42
##   HintBar       -34..-12
##   QuestPanel    x 24..434, bottom-anchored, content-sized
##   Minimap       bottom-right, offsets -220..-24 on both axes
const BAND_TOP := 170.0
const BAND_BOTTOM := 114.0
const BAND_OBJECTIVE_W := 448.0
const BAND_OBJECTIVE_H := 264.0
const BAND_MINIMAP_W := 240.0
const BAND_MINIMAP_H := 238.0
## The furthest a caption will slide, in screen units, to get out of a band.
## Past this the move itself is more misleading than the overlap, so it fades.
##
## Round 6: raised from 118. The bottom edge is where this number is spent, and
## 118 was just under what the bottom row of captions actually needs. Measured
## off the round-5 production frame: "ROLLBACK" (authored world y 856) lands at
## canvas y 1054..1090 against a bottom band that starts at 966, so it asks for
## ~124 units — six past the old cap. It therefore skipped the slide, hid, and
## the frame kept the half-glyph text at the viewport edge for the ~0.4s of
## fade. "POSTMORTEMS (blameless)" and gpu_mines' "COOLING" lost the same way.
## At the region zoom — 1.35 canvas units per world unit, off
## `scenes/player/player.tscn` — 156 canvas units is 115.6 world units, so the
## slide stays the same order of magnitude as the build-time ladder (112) rather
## than becoming a second, larger and invisible displacement system. DODGE_MAX
## is that number in world units and MUST be kept in step with this one; see the
## note there for what happens when it is not.
const PUSH_MAX := 156.0

## Clear air a plate keeps from the left and right VIEWPORT edges. The bands
## above cover the top and bottom edges already (both run to the frame edge);
## nothing covered the sides, and a plate cut off by the side of the frame reads
## as the same clipping bug as one cut off by the bottom.
const BAND_EDGE := 18.0

## Boss reserved bands, added to the top/bottom bands only while a boss is alive.
## Read off scripts/combat/boss_hud.gd, whose own header names "y -230..-130,
## x centre +-318" as "the band world text is expected to dodge":
##   announcement card  BAND_TOP 222 .. + ENTRANCE_H 138  ->  222..360
##   status frame       offset_top -218 - 12 .. -218 + FRAME_H 78 + 10
## Both are taken full-width rather than as their real centred rects (1040 and
## 636 wide). During a boss fight the screen belongs to the fight; a flavour
## caption that fades at the left edge of the announcement band costs nothing,
## and a full-width band is one number the boss HUD owner can re-check instead
## of a pair of rects that have to track its anchors.
const BOSS_BAND_TOP := 372.0
const BOSS_BAND_BOTTOM := 242.0

## The furthest the live dodge will ever carry a plate from its home, in world
## units. Named because the player-clearance pass and the HUD push now share it.
##
## It has to be PUSH_MAX expressed in world units, or the two caps silently
## disagree and the smaller one wins. `_hud_push` measures and caps in CANVAS
## units and only raises `_hud_hide` past PUSH_MAX; `_retarget` then re-caps the
## same vector in WORLD units against this number. At 96 that clawed back
## 26 canvas units of the exact margin PUSH_MAX was raised to buy, and — worse —
## it did so WITHOUT raising `_hud_hide`, so a caption that needed more than
## 96 world units of lift held still at full alpha with its tail under the
## ability bar. Which is the defect, not the fix for it.
##
## The conversion is the camera's zoom, which is what
## `get_global_transform_with_canvas().get_scale()` returns here: 1.35
## (`scenes/player/player.tscn`, `zoom = Vector2(1.35, 1.35)` — NOT the ~1.6 an
## earlier draft of the PUSH_MAX note assumed). 156 / 1.35 = 115.6, so 116.
## camera_fx can zoom OUT a few percent while the player is sprinting, which
## makes the world-unit cost of a band briefly larger than this; the caption is
## then a few units short of clear for as long as the sprint lasts, which is
## still strictly better than the plate holding still inside the band.
const DODGE_MAX := 116.0

## Where the player's own pixels are, relative to their global_position (which
## is at their FEET).
##
## MEASURED, not guessed, off the round-5 localhost frame — spawn (720, 640),
## camera clamped to y 624 at zoom 1.35, canvas 2234.5x1080 at PNG scale
## 0.85926 (the conversion boss_hud.gd's header documents). The character's ink
## runs world x 695..753, y 556..672. The box is deliberately WIDER than that
## (674..766) — a caption that stops one pixel from a shoulder still reads as
## touching it — and now runs to y 674 so it covers the feet the sprite actually
## stands on rather than stopping six units above them.
##
## It does NOT include the "[E]" prompt. An earlier draft of this note claimed
## the box was grown upward to take that in; it is not, and it does not need to
## be. `player.gd::_update_prompt` anchors the prompt to the INTERACTABLE
## (`closest.global_position + Vector2(-70, 34 or -64)`), not to the player, so
## it is nowhere near this rect. The prompt's own protection is that
## interactables carry reserved boxes.
##
## Round 6, and this is the whole of defect 1: the old test asked whether the
## player's POSITION was inside the plate. A caption hanging at chest height
## never contains the feet, so localhost's "talk to Claude first ->" (plate at
## world y 598..626, spawn at y 640) never counted as an overlap at all. It sat
## across the character's head and torso in every localhost frame, dialogue
## included. A body is a box, not a point.
const PLAYER_BODY := Rect2(-46.0, -84.0, 92.0, 118.0)
## Air the caption keeps around that body before it counts as an overlap...
const PLAYER_CLEAR := 18.0
## ...and the wider ring in which it merely dims out of the character's way.
const PLAYER_RING := 58.0

## Density (defect 4: the apartment drew fourteen captions at once). How many
## captions of AT LEAST this one's priority may be nearer to the player before
## this one is treated as crowded out, and the floor the crowding decay stops
## at. Wayfinding (priority 3) is exempt — it is the answer to "what do I do
## next" and is never the thing that gets quieter.
const CROWD_BUDGET := 4
const CROWD_DECAY := 0.76
const CROWD_MIN := 0.34

## How much of its own plate a BOLTED caption may have inside a reserved band
## before it gives up and fades. A bolted sign is a region headline: it cannot
## slide (its neon tube, brackets and floor pool are positioned from `box` at
## BUILD time and nothing re-parents them), so fading is the only yield it has —
## which makes the decision to fade an all-or-nothing one and worth measuring
## properly.
##
## It used to be measured on the PUSH DISTANCE alone, against a flat ten units.
## But the push distance is the distance to the outside of the BAND, and every
## band carries a safety margin over the HUD it protects: BAND_OBJECTIVE_W is
## 448 against a QuestPanel whose real right edge is 434. A headline whose plate
## starts at x=433 — touching the panel, overlapping it by less than one unit —
## was therefore asked to move 15, cleared the 10-unit dead zone, and switched
## itself off. token_vault's "TOKEN RESERVES" lost to exactly that in the
## round-5 capture, by 1.7 units, and because region_builder._sign only checks
## `lbl.visible` at build time the frame kept the neon tube, the two brackets
## and the floor pool hanging over bare floor with no sign under them.
##
## So: hide on how much of the plate is ACTUALLY inside a band, not on how far
## it is from the band's outside edge. A twelfth of a headline clipped by a
## panel edge is invisible; a quarter of one printed through the cycle readout
## is the defect the bands exist to prevent.
const BOLT_CLIP := 0.12

## Distance fade. Near everything is full strength; past FADE_NEAR a caption
## dims toward its priority floor, and a low-priority gag is culled outright
## once it is further away than the player could plausibly be reading it.
##
## Round 6: FADE_NEAR was 560, which is most of a room. Every caption in the
## localhost frame was inside it, so the ramp never engaged and all fourteen
## drew at the same strength — the flat wall of text the critic counted. 340 is
## about "the furniture you are standing among"; past it the ramp starts doing
## the job it was written for.
const FADE_NEAR := 340.0
const FADE_FAR := 1180.0
## Length of the dissolve at the cull radius. A hard cut there reads as a bug.
const CULL_RAMP := 160.0
## Cull radius by priority. A gag you have walked away from is finished; a
## furniture caption survives most of a room; wayfinding never culls, because
## the sign that says where to go has to be readable from where you are.
const CULL_BY_PRIO := [820.0, 820.0, 1420.0, 1.0e9]
## Ceiling by priority, so a static frame shows its own reading order instead of
## twenty equally bright plates. The gap is small on purpose — a gag at 0.86 is
## still perfectly readable, it just stops competing with the sign next to it.
const PEAK_BY_PRIO := [0.86, 0.86, 0.94, 1.0]

## Layout state for the region currently being built. Builds are strictly
## sequential (one region exists at a time), so static state is safe here and
## saves threading a layout object through forty call sites.
static var _claims: Array = []
static var _prios: Array = []
static var _owners: Array = []
static var _bounds := Rect2(0.0, 0.0, 1280.0, 960.0)
static var _phase_seed := 0.0
static var _box_cache: Dictionary = {}
static var _style_cache: Dictionary = {}
static var _font_cache: Dictionary = {}
static var _add_mat: CanvasItemMaterial

## Every label currently in the tree, for the density pass — each one needs to
## know how many captions of its own weight or heavier are nearer to the player
## than it is. Deliberately an untyped Array: `Array[WorldLabel]` inside the
## class that declares WorldLabel is exactly the kind of identifier this file
## has silently died on before (HANDOVER 6b). Entries are added in _ready and
## removed in _exit_tree, and pruned of freed instances in begin().
static var _live: Array = []
## Resolved once. Looked up by PATH and called by NAME rather than through the
## `UIManager` global, so a rename or a missing autoload degrades to "no modal
## is open" instead of killing every caption in the game.
static var _ui: Node = null
## Boss-band state, shared by every label and recomputed at most once per
## retarget interval — twenty labels each walking the enemy group at 8Hz is
## twenty times more scanning than the answer is worth.
static var _boss_on := false
static var _boss_ms := -10000

## The label's own footprint in world space, so callers can hang a neon fixture
## or a bracket off the plate instead of guessing where the text ended up.
var box := Rect2()

var _home := Vector2.ZERO
var _size := Vector2.ZERO
var _center := Vector2.ZERO
var _phase := 0.0
var _t := 0.0
var _tick := 0.0
var _do_bob := true
var _do_fade := true
var _alpha := 1.0
var _target := 1.0
var _floor := 0.34
var _cull := FADE_FAR
var _settle := 0.955
## Headline plates have a neon tube, two brackets and a floor pool positioned
## from `box` by the region builder AT BUILD TIME (region_builder._sign,
## localhost_builder). Nothing re-parents them, so every runtime displacement of
## the plate — the dodge, the appear slide, the settle scale — slides the sign
## out from under its own fixture. A bolted label therefore holds its position
## and yields with alpha alone.
var _bolted := false
var _appear := 0.0
var _dodge := Vector2.ZERO
var _dodge_to := Vector2.ZERO
var _hud_hide := false
## Largest fraction of this label's plate that any one reserved HUD band covers,
## recomputed with the push in _hud_push. See BOLT_CLIP.
var _hud_over := 0.0
var _player: Node2D = null
## Authoring priority, kept on the node so the density pass can rank captions
## against each other (the static `_prios` list is layout-time only and its
## indices do not survive an eviction).
var _prio := 1
## Ceiling this label's alpha may reach, from PEAK_BY_PRIO.
var _peak := 1.0
## Distance from the player to this label's centre, refreshed each retarget so
## that the density pass can read it off the neighbours without twenty labels
## each recomputing twenty distances. Starts effectively infinite so a label that
## has not had its first retarget yet is never counted as "nearer" than one that
## has — otherwise every caption in a freshly built region crowds every other.
var _dist := 1.0e9
## Plateless styles (`tag` on a monitor face, `plaque` on a wall poster) are part
## of the artwork they sit on: the poster's frame IS their plate and the monitor
## bezel IS their border. Sliding one is worse than any overlap it could be
## sliding out of, so like a bolted headline they yield with alpha alone.
var _pinned := false

# --------------------------------------------------------------- layout -----

## Call once at the top of a region build. `bounds` is the room rect; labels are
## clamped inside it, so a nudge can never push text into a wall or off-world.
static func begin(bounds: Rect2) -> void:
	_claims.clear()
	_prios.clear()
	_owners.clear()
	_bounds = bounds
	_phase_seed = 0.0
	# The previous region's labels deregister themselves in _exit_tree, but a
	# region torn down with free() rather than queue_free() can leave a dangling
	# entry behind; the density pass must never walk one.
	var alive: Array = []
	for o in _live:
		if o != null and is_instance_valid(o):
			alive.append(o)
	_live = alive

## Reserve a box drawn by somebody else — a portal's destination plate, an NPC's
## name tag, a monitor face with baked-in text. Reserved first, at max priority,
## so signs move out of THEIR way rather than the other way round.
static func reserve(rect: Rect2) -> void:
	_claims.append(rect)
	_prios.append(99)
	_owners.append(null)

## Text size measured from the real font, not guessed from character counts. The
## old estimate (chars * size * 0.56) under-measured wide glyphs, which is how
## captions ended up wider than the space that had been claimed for them.
static func measure(text: String, font_size: int) -> Vector2:
	return _measure(text, font_size, 0)

## Same, for a tracked (letter-spaced) variation — tracking widens every glyph
## advance, so a title measured with the untracked font would under-claim.
static func _measure(text: String, font_size: int, track: int) -> Vector2:
	var key := "%d|%d|%s" % [font_size, track, text]
	if _box_cache.has(key):
		return _box_cache[key]
	var size := Vector2.ZERO
	var font: Font = _face(track)
	if font:
		size = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	if size.x < 2.0:
		var lines := text.split("\n")
		var widest := 0
		for l in lines:
			widest = maxi(widest, l.length())
		size = Vector2(float(widest) * float(font_size) * 0.62 + float(widest * track),
			float(lines.size()) * float(font_size) * 1.35)
	_box_cache[key] = size
	return size

## Does this line read as a NAME rather than as prose? Deliberately strict: the
## cost of a false positive (a sentence cut in half by a divider rule, its tail
## set smaller and dimmer) is much higher than the cost of a false negative (the
## caption renders as one block, which is what it did before the split existed).
##
## A title is short, carries no sentence punctuation at all, and is either
## uppercase-dominant ("PLANT", "SERVER RACK", "PIZZA ARCHAEOLOGY") or a single
## unbroken token ("node_modules"). Every wrapped sentence in the corpus fails on
## the punctuation test or on having a space with lowercase words on both sides.
static func _is_title(s: String) -> bool:
	var t := s.strip_edges()
	if t.is_empty() or t.length() > 28:
		return false
	for ch: String in [".", "!", "?", ":", ";", ","]:
		if t.contains(ch):
			return false
	var up := 0
	var lo := 0
	for i in t.length():
		var code := t.unicode_at(i)
		if code >= 65 and code <= 90:
			up += 1
		elif code >= 97 and code <= 122:
			lo += 1
	if up == 0 and lo == 0:
		return false
	if up >= lo:
		return true
	return not t.contains(" ")

## Cached letter-spaced faces. Tracking is the house style for titles across the
## whole UI (see the HUD region banner); world signs now match it instead of
## being the one place headings are set solid.
static func _face(track: int) -> Font:
	var base: Font = ThemeDB.fallback_font
	if track <= 0 or base == null:
		return base
	var key := "t%d" % track
	if _font_cache.has(key):
		return _font_cache[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.set_spacing(TextServer.SPACING_GLYPH, track)
	_font_cache[key] = fv
	return fv

# ----------------------------------------------------------- construction ---

## Build a world label. Returns the node (already parented) — hidden rather than
## overlapping when the room has no space left and this label is expendable.
##
## When the first line reads as a NAME ("PLANT\nstatus: deprecated"), it is set
## as a TITLE over a quieter SUBTITLE; when it reads as prose ("Egress fees apply
## \nto leaving. And to thinking.") the caption stays one uniform block, because
## a divider through the middle of a sentence is worse than no hierarchy at all.
## See _is_title(). Nothing about the API changed either way.
##
## opts: size (int font size), style (see STYLES), priority (int, higher wins a
## contested spot), z (int z_index override), color (text colour override),
## plate/bob/fade/claim/bar (per-call overrides of the style preset).
static func add(parent: Node2D, pos: Vector2, text: String, accent: Color, opts: Dictionary = {}) -> WorldLabel:
	var style_name := str(opts.get("style", "plate"))
	var style: Dictionary = STYLES.get(style_name, STYLES["plate"])
	var headline := style_name == "headline"
	var font_size := int(opts.get("size", 12))
	var want_plate := bool(opts.get("plate", style["pl"]))
	var want_bob := bool(opts.get("bob", style["bob"]))
	var want_fade := bool(opts.get("fade", style["fade"]))
	var want_claim := bool(opts.get("claim", style["claim"]))
	var bar_w := float(opts.get("bar", style["bar"]))
	var prio := int(opts.get("priority", 1))
	var z := int(opts.get("z", Z_PLATE))
	var text_col: Color = _readable(accent)
	if opts.has("color"):
		text_col = opts["color"]

	# --- typographic split -------------------------------------------------
	# ONLY where the first line is genuinely a title. Half this game's captions
	# are one sentence wrapped across two lines — "Egress fees apply / to leaving.
	# And to thinking.", "Do not spend it all / at once. Or at all.", "Maintained
	# by 1 human / and a lot of guilt" — and putting a hairline rule through the
	# middle of a sentence, then setting its second half smaller and dimmer, is
	# worse than not splitting at all: it severs the clause the joke turns on.
	# When _is_title() declines, the caption renders exactly as it did before this
	# pass — one uniform block — so the fallback is the known-good look.
	var nl := text.find("\n")
	var head := text if nl < 0 else text.substr(0, nl)
	var rest := "" if nl < 0 else text.substr(nl + 1)
	var split := not rest.is_empty() and _is_title(head)
	var title := head if split else text
	var sub := rest if split else ""
	# Tracking is the house treatment for NAMES, not for prose. A letter-spaced
	# sentence at 11px is harder to read, not more designed.
	var track := 2 if headline else (1 if (split or (nl < 0 and _is_title(text))) else 0)
	var sub_size := maxi(9, font_size - 1)
	# The subtitle is the same hue, walked halfway to TEXT_DIM. Same family, one
	# step quieter — hierarchy without inventing a second palette.
	var sub_col := text_col.lerp(TEXT_DIM, 0.46)

	# Both blocks are built (unparented) BEFORE the box is sized, so the plate is
	# measured from the Labels that will actually be drawn rather than from a
	# second, parallel estimate that can disagree with them by a pixel or two.
	var outline := 3 if want_plate else 5
	var title_node := _text_node(title, font_size, track, text_col, outline, want_plate)
	var sub_node: Label = null
	if not sub.is_empty():
		sub_node = _text_node(sub, sub_size, 0, sub_col, outline, want_plate)
	var title_h := title_node.size.y
	var sub_box: Vector2 = sub_node.size if sub_node != null else Vector2.ZERO
	var gap := TITLE_GAP if sub_node != null else 0.0
	var text_size := Vector2(maxf(title_node.size.x, sub_box.x), title_h + gap + sub_box.y)

	var pad := PAD if want_plate else Vector2(3.0, 2.0)
	var box_size := text_size + pad * 2.0 + Vector2(bar_w, 0.0)
	var placed := _place(pos, box_size, prio, want_claim)
	var at: Vector2 = placed["pos"]

	var node := WorldLabel.new()
	node.name = "WorldLabel"
	node.position = at
	node.z_index = z
	node.box = Rect2(at, box_size)
	node._home = at
	node._size = box_size
	node._center = at + box_size * 0.5
	node._do_bob = want_bob
	node._do_fade = want_fade
	node._floor = 0.18 if prio <= 1 else (0.46 if prio >= 3 else 0.32)
	node._prio = prio
	var tier := clampi(prio, 0, 3)
	node._cull = float(CULL_BY_PRIO[tier])
	node._peak = float(PEAK_BY_PRIO[tier])
	node._pinned = not want_plate
	# Modals and dialogues either pause the tree (pause menu, quest log, Dream
	# App, map, event ticket) or hold it while a panel covers the lower third
	# (dialogue). A caption frozen at full alpha behind a semi-transparent panel
	# is the bleed-through defect; one that keeps ANIMATING under it is HANDOVER
	# 4.4. So: always processing, and _retarget's first act is to notice the
	# modal and go quiet. Nothing in this class tweens, so nothing can freeze
	# half-way through.
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	# A headline carries a bolted-on neon fixture positioned from `box`; moving
	# or scaling the plate under it would slide the tube off its brackets.
	node._settle = 1.0 if headline else 0.955
	node._bolted = headline
	_phase_seed += 1.37
	node._phase = _phase_seed
	var slot := int(placed["slot"])
	if slot >= 0 and slot < _owners.size():
		_owners[slot] = node
	parent.add_child(node)

	if want_plate:
		_build_plate(node, box_size, accent, bar_w, headline)

	var tx := pad.x + bar_w
	if sub_node != null and want_plate:
		# Hairline rule in the accent, sitting in the middle of the title gap:
		# the divider that makes "title" and "subtitle" read as two registers
		# rather than as one caption that happens to wrap.
		var rule := ColorRect.new()
		rule.size = Vector2(maxf(8.0, text_size.x - 6.0), 1.0)
		rule.position = Vector2(tx, pad.y + title_h + gap * 0.5)
		rule.color = Color(accent.r, accent.g, accent.b, 0.26)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(rule)

	if headline:
		# HDR trick #1 (VISUAL_BIBLE): a duplicated overbright copy under the
		# crisp one, so a region name blooms instead of merely being bright.
		var glow_lbl := _text_node(title, font_size, track,
			Color(text_col.r * 1.7, text_col.g * 1.7, text_col.b * 1.7, 0.34), 0, want_plate)
		glow_lbl.material = _additive()
		glow_lbl.position = Vector2(tx, pad.y)
		node.add_child(glow_lbl)

	title_node.position = Vector2(tx, pad.y)
	node.add_child(title_node)
	if sub_node != null:
		sub_node.position = Vector2(tx, pad.y + title_h + gap)
		node.add_child(sub_node)

	_build_leader(node, pos, at, box_size, accent, want_claim)

	if not bool(placed["ok"]):
		# The room genuinely ran out of clear space and this label is expendable.
		# Silence beats two captions sharing pixels.
		node.visible = false
		node.set_process(false)
	elif not want_bob and not want_fade:
		# Printed matter never moves, never bobs and never distance-fades, so it
		# skips the settle entirely — but it does NOT get set_process(false) any
		# more. It still has to notice a modal covering the screen and get out of
		# the way with everything else, and it still has to yield if the camera
		# carries it under the HUD. With _do_bob and _do_fade both off, _process
		# is a handful of floats and one alpha compare: cheaper than the branch
		# that used to justify switching it off.
		node._appear = 1.0
	return node

## One line (or block) of world text. Outline + drop shadow together: the
## outline holds the glyph edge against a bright floor (the API Bazaar's pink
## diamond plaza is brighter than the plate under it), the shadow separates the
## whole block from whatever is directly behind it.
static func _text_node(text: String, font_size: int, track: int, col: Color, outline: int, plated: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	var face := _face(track)
	if face:
		lbl.add_theme_font_override("font", face)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.004, 0.006, 0.02, 0.95))
	lbl.add_theme_constant_override("outline_size", outline)
	lbl.add_theme_constant_override("line_spacing", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55 if plated else 0.75))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	# Measured from the font, not from the Label: a Control that is not yet in
	# the tree has no resolved theme cache, so its own minimum size can come back
	# as zero. Whichever number is bigger wins, plus a couple of pixels for glyph
	# bearing and the outline — the plate must never be narrower than its text.
	var m := _measure(text, font_size, track)
	lbl.reset_size()
	lbl.size = Vector2(maxf(m.x, lbl.size.x) + 4.0, maxf(m.y, lbl.size.y) + 2.0)
	return lbl

## Glass plate: BASE at ~88%, hairline accent-tinted border, 6px radius, and a
## soft drop shadow so the plate sits ABOVE the scenery instead of being printed
## on it — plus an overbright accent bar down the left edge that blooms on its
## own (HDR trick #1 in the bible: modulate above 1.0).
static func _build_plate(node: Node2D, size: Vector2, accent: Color, bar_w: float, headline: bool) -> void:
	var panel := Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _plate_style(accent, headline))
	node.add_child(panel)
	if bar_w <= 0.0:
		return
	var bar := ColorRect.new()
	bar.size = Vector2(bar_w, maxf(4.0, size.y - 6.0))
	bar.position = Vector2(3.0, 3.0)
	bar.color = Color(accent.r * 1.9, accent.g * 1.9, accent.b * 1.9, 0.95)
	bar.material = _additive()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(bar)
	if not headline:
		return
	# Headline signs get an underlit base: the plate reads as a lit fixture
	# rather than a sticker, and region names separate from flavour text.
	var glow := ColorRect.new()
	glow.size = Vector2(maxf(6.0, size.x - 10.0), 2.0)
	glow.position = Vector2(5.0, size.y - 4.0)
	glow.color = Color(accent.r * 1.7, accent.g * 1.7, accent.b * 1.7, 0.85)
	glow.material = _additive()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(glow)

## Plateless styles (`tag` on a monitor face, `plaque` on a wall poster) get no
## backing at all on purpose — a scrim there would cover the artwork the text is
## supposed to be part of. Their legibility floor is the heavier outline plus the
## drop shadow in _text_node, which holds a glyph edge against a bloomed screen
## without hiding a pixel of it.
##
## When the ladder had to carry a caption off its subject, mark WHICH WAY it
## went — with a tick, not with a ray.
##
## The round-5 version drew a Line2D from the plate edge all the way to the
## subject's centre. With the old 208-unit ladder (and worse, with a clamp that
## could displace a caption authored outside the room by far more than that),
## that produced accent-coloured beams hundreds of units long across the play
## area. Two frames' worth of QA read them as lasers, because the vault's
## security lattice and the mines' heat beams are exactly that shape and hue.
##
## The connector is now a short elbow stub off the plate edge: ~7 units straight
## out along the dominant axis, then ~8 along the bearing to the subject, with a
## 2-unit terminator. It is 1px, unlit (no additive material — an overbright
## hairline blooms into precisely the beam this is replacing), and dim. It says
## "the thing I name is over there" as a piece of typography and then stops.
## Association beyond that is DISPLACE_MAX's job, not the line's: the caption is
## never more than a plate-width from its subject in the first place.
static func _build_leader(node: Node2D, want: Vector2, at: Vector2, size: Vector2, accent: Color, claimed: bool) -> void:
	if not claimed:
		return
	var d := want - at
	# A one- or two-rung nudge is not a displacement worth annotating, and a mark
	# on every crowded caption is its own kind of clutter.
	if d.length() < 46.0:
		return
	var dir := d.normalized()
	var c := size * 0.5
	# Where the bearing leaves the plate: the nearer of the vertical and the
	# horizontal edge crossing, plus 2 units of air.
	var tx := c.x / maxf(absf(dir.x), 0.0001)
	var ty := c.y / maxf(absf(dir.y), 0.0001)
	var edge := c + dir * (minf(tx, ty) + 2.0)
	# Dominant axis first, so the stub leaves the plate square to its own edge
	# and the kink reads as a drawn elbow rather than as a stray diagonal.
	var axis := Vector2(signf(dir.x), 0.0) if absf(dir.x) >= absf(dir.y) else Vector2(0.0, signf(dir.y))
	var knee := edge + axis * 7.0
	var tip := knee + dir * 8.0
	# Never let the tick land ON somebody else's text. The round-5 leader put its
	# terminator out at the SUBJECT, and in the gpu_mines frame one landed inside
	# the plate of "Do not open. Heat." — a small dark-cored diamond sitting on
	# the first word, which reads as a tofu box, not as an annotation. The stub
	# is short now and this is a belt-and-braces guard, but a mark whose whole
	# job is to point at something must not be mistakable for a glyph.
	var tip_world := at + tip
	var mine := Rect2(at, size)
	# NOT `c` (this function's plate centre, declared above) and NOT `claimed`
	# (this function's own parameter). A loop variable that shadows either is a
	# hard parse error in GDScript 4 — "There is already a variable named ...
	# declared in this scope", raised for any name already live in an ENCLOSING
	# block, not just the same one — and a parse error in THIS file deletes every
	# caption in the game while all 28 suites still pass (HANDOVER 6b).
	for taken: Rect2 in _claims:
		if taken == mine:
			continue
		if taken.grow(3.0).has_point(tip_world):
			return
	var line := Line2D.new()
	line.name = "Leader"
	line.points = PackedVector2Array([edge, knee, tip])
	line.width = 1.0
	line.default_color = Color(accent.r, accent.g, accent.b, 0.30)
	line.antialiased = false
	node.add_child(line)
	# A 2-unit terminator closes the tick off. It sits at the END OF THE STUB,
	# not out at the subject — an unattached diamond floating in the middle of
	# the room is set dressing nobody asked for.
	var pin := Polygon2D.new()
	pin.name = "LeaderPin"
	pin.polygon = PackedVector2Array([
		tip + Vector2(0.0, -2.0), tip + Vector2(2.0, 0.0),
		tip + Vector2(0.0, 2.0), tip + Vector2(-2.0, 0.0)])
	pin.color = Color(accent.r, accent.g, accent.b, 0.44)
	node.add_child(pin)

# ------------------------------------------------------------- internals ----

## One StyleBoxFlat per accent+weight combo — ~20 labels a region share a
## handful of instances instead of allocating one each (bible: reuse resources
## wherever params are identical).
static func _plate_style(accent: Color, headline: bool) -> StyleBoxFlat:
	var key := accent.to_html(false) + ("H" if headline else "N")
	if _style_cache.has(key):
		return _style_cache[key]
	var sb := StyleBoxFlat.new()
	# Round 5: +0.04 alpha. The pink diamond plaza in api_bazaar and the gold
	# slab in token_vault are both brighter than the plate was opaque.
	sb.bg_color = Color(PLATE_BG.r, PLATE_BG.g, PLATE_BG.b, 0.94 if headline else 0.88)
	sb.border_color = Color(
		lerpf(PLATE_LINE.r, accent.r, 0.45),
		lerpf(PLATE_LINE.g, accent.g, 0.45),
		lerpf(PLATE_LINE.b, accent.b, 0.45),
		0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0.0, 3.0)
	_style_cache[key] = sb
	return sb

static func _additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

## Region accents are authored for neon, not for reading. ACID #A8FF3E and GOLD
## #FFD34D are fine; ember #FF6B2D, heat #FF3D2D, VIOLET #8B5CF6 and corporate
## #4D7CFF are mud at 11px — the captured GPU Mines frame is a whole region of
## dark-red text on a bright-red floor. Label colour is lifted toward WHITE_HOT
## until it clears a readability floor; the accent bar keeps the hue.
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
##   2. the home slot, evicting strictly lower-priority captions — a region name
##      or a wayfinding sign beats a gag for the spot it actually belongs in,
##   3. the least-bad overlap within the cap (see _least_bad), and only then
##      silence.
## A rung whose CLAMPED position lands further than the cap FROM THE HOME SLOT
## is skipped, not taken. Measuring from home rather than from the authored
## point is deliberate: the clamp that pulls a wall-hugging caption into the room
## is not a displacement the ladder chose, and counting it against the cap
## disabled the ladder entirely for those captions (see the note in the body).
static func _place(pos: Vector2, size: Vector2, prio: int, claim: bool) -> Dictionary:
	if not claim:
		return {"pos": pos, "ok": true, "slot": -1}
	# Displacement is measured from the HOME SLOT, not from the authored point.
	# _clamp_in is not optional — a caption hung near a wall has to come inside
	# the room whatever the cap says — so measuring from `pos` made the cap
	# swallow the clamp itself: for any caption whose clamped home is more than
	# DISPLACE_MAX from where it was authored, EVERY rung clamps to more than the
	# cap, the loop skips all of them, and the ladder silently becomes a no-op
	# with eviction or silence as the only remaining outcomes. The anti-beam
	# invariant is "the LADDER may not carry a caption more than DISPLACE_MAX",
	# and the ladder starts at home.
	var home := _clamp_in(pos, size)
	for off: Vector2 in LADDER:
		var at := _clamp_in(pos + off, size)
		if (at - home).length() > DISPLACE_MAX:
			continue
		if _colliders(Rect2(at, size)).is_empty():
			return {"pos": at, "ok": true, "slot": _claim(Rect2(at, size), prio)}
	# Nothing clear anywhere on the ladder. Wayfinding and region names outrank
	# flavour gags: evict the losers from the home spot and take it.
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
## stays under this caption's share of its own area (OVERLAP_TOL, doubled for a
## region name — see OVERLAP_TOL_HEAD).
##
## This exists because the anti-beam cap took reach away from the ladder, and the
## cheap way to spend that reach would have been to hide more captions. Silence
## is the right answer to a full room, but it is the wrong answer to a room where
## the caption would have fitted with six pixels of its shadow clipped. The
## displacement term in the cost is deliberately small — it only breaks ties
## between slots that overlap equally, keeping the caption near its subject.
static func _least_bad(pos: Vector2, size: Vector2, prio: int) -> Dictionary:
	var area := maxf(1.0, size.x * size.y)
	var tol := OVERLAP_TOL_HEAD if prio >= 3 else OVERLAP_TOL
	# Same origin as _place: from the clamped home, so a caption hung near a wall
	# still gets the whole ladder instead of having every rung skipped.
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
		# The room is genuinely full: even the least-bad slot buries more of this
		# caption than it can afford. Silence beats a smeared block, and it
		# certainly beats dragging the plate across the floor to find air.
		return {"pos": home, "ok": false, "slot": -1}
	# Anything this label OUTRANKS that is still touching the slot it settled on
	# gets evicted, exactly as tier 2 would have done at home. _overlap_area only
	# scores claims at or above `prio`, so without this pass a tier-3 caption
	# could come to rest on a gag it outranks and both would draw.
	# Descending indices: removing from the front would shift the rest.
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
## not the 6px-grown test _colliders uses: near-misses are what tier 3 is looking
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

## Indices of every claim this box would touch. 6px of air around each plate:
## boxes that merely kiss still read as one smeared block at 1080p, and the
## plate now casts a 7px shadow that has to land on something other than the
## next caption's border.
static func _colliders(r: Rect2) -> Array:
	var out: Array = []
	var grown := r.grow(6.0)
	for i in _claims.size():
		if (_claims[i] as Rect2).intersects(grown):
			out.append(i)
	return out

## Round 6 raised the bottom inset from 34 to 60. The bottom of a room is where
## the camera stops following and where the whole of the HUD lives, so a caption
## authored down there spends its entire life inside the ability-bar band asking
## for a screen-space rescue. Twenty-six units of build-time headroom is cheaper
## than a permanent runtime push, and the ladder still has to find it a clear
## slot afterwards either way.
static func _clamp_in(at: Vector2, size: Vector2) -> Vector2:
	var lo := _bounds.position + Vector2(26.0, 78.0)
	var hi := _bounds.position + _bounds.size - size - Vector2(26.0, 60.0)
	return Vector2(clampf(at.x, lo.x, maxf(lo.x, hi.x)), clampf(at.y, lo.y, maxf(lo.y, hi.y)))

# --------------------------------------------------------------- runtime ----

func _ready() -> void:
	modulate.a = _alpha
	if not _live.has(self):
		_live.append(self)

func _exit_tree() -> void:
	_live.erase(self)

## Float, settle, dodge and distance fade. No allocations: the alpha/dodge
## targets are recomputed at ~8Hz, everything per-frame is a handful of floats.
func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.12
		_retarget()
	if _appear < 1.0:
		_appear = minf(1.0, _appear + delta * 4.0)
	if _dodge != _dodge_to:
		_dodge = _dodge.move_toward(_dodge_to, delta * 210.0)
	# Cubic ease-out on the settle: it arrives quickly and stops without a bounce.
	var e := 1.0 - pow(1.0 - _appear, 3.0)
	var off := _dodge
	if not _bolted:
		off.y += (1.0 - e) * 6.0
	if _do_bob:
		off.y += sin(_t * 1.15 + _phase) * 2.0
	var s := _settle + (1.0 - _settle) * e
	# Guarded: a headline never scales at all, and every other label stops
	# scaling a quarter of a second in. Writing an unchanged scale still dirties
	# the transform for every caption in the room, every frame, forever.
	if not is_equal_approx(scale.x, s):
		scale = Vector2(s, s)
	position = _home + off + _size * (0.5 * (1.0 - s))
	if not is_equal_approx(_alpha, _target):
		_alpha = move_toward(_alpha, _target, delta * 2.4)
		modulate.a = _alpha

func _retarget() -> void:
	# A dialogue or a modal owns the screen. World captions are set dressing
	# BEHIND that panel, and every panel in this game is semi-transparent, so
	# they do not disappear — they show through it as ghost text competing with
	# the line the player is actually reading (the localhost dialogue frame has
	# "COUCH" and "PIZZA ARCHAEOLOGY" printed through the dialogue box). Fade out
	# and stop measuring; everything comes back when the panel closes.
	if _blocked():
		_target = 0.0
		return
	_measure_player()
	var push := _hud_push()
	if _bolted or _pinned:
		# Cannot move — a headline is bolted to its own neon fixture and a
		# plateless caption is part of the poster or monitor face it sits on
		# (see _bolted / _pinned). Both yield the only way they can, by fading.
		#
		# The small dead zone matters — a region name is the most important caption
		# in the room, and hiding it the instant its plate grazes a panel edge
		# by two pixels makes it strobe on and off as the player walks along
		# that boundary. Ten world units of overlap is tolerable; more is not.
		# _hud_push() has already raised _hud_hide for the cases where no move
		# would have helped anyway; never clear that, only add to it.
		#
		# Both terms are needed. The push is what says "this is in a band at
		# all"; the clip fraction is what says the overlap is worth losing the
		# region's name over, instead of the band's own safety margin brushing a
		# plate that never touched the HUD (see BOLT_CLIP).
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
		# The three terms COMPETE, they do not compound. Each one already carries
		# its own stated floor — the distance ramp bottoms out at `_floor` (0.18
		# / 0.32 / 0.46 by priority) and the crowd decay at CROWD_MIN (0.34) —
		# and those floors exist because "quieter than its neighbours" and
		# "invisible" are different states. Multiplying them threw both away: a
		# priority-2 furniture caption across the room with five captions nearer
		# than it landed at 0.486 x 0.34 x 0.94 = 0.155, which on an 88%-opaque
		# plate over a dark floor is not a quiet caption, it is a smudge. Half
		# the captions in the apartment resolved to that. Taking the smallest
		# term keeps the reading order the density pass was written for and
		# honours the floors the same pass declared.
		vis = minf(_peak, minf(_by_distance(), _crowd()))
	# Last, and after the HUD dodge is known, because this pass adds to it: the
	# character is the one thing on screen no caption may ever share pixels with.
	if vis > 0.0:
		vis = _clear_of_player(vis)
	# Coming back into view replays the settle, so a caption resolving out of
	# the dark as you approach reads as arriving rather than as popping on.
	if vis > 0.02 and _target <= 0.02:
		_appear = 0.0
	_target = vis

## Is a dialogue or a full-screen panel up? Resolved by PATH and called by NAME:
## a hard `UIManager.has_blocking_ui()` would be a compile-time dependency of the
## one class in this project whose death takes every caption in the game with it
## (HANDOVER 6b), and this file has already paid that bill once. Missing autoload
## or renamed method degrades to "nothing is blocking", which is the pre-round-6
## behaviour rather than a black hole.
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

## Density (defect 4). Fourteen captions in one apartment is not fourteen pieces
## of information, it is a wall of text with no reading order — the eye picks
## none of them. Rather than cull by author (which would mean deleting jokes) or
## by a fixed cap (which would make captions blink in and out as the player
## walks), each caption asks how many captions of AT LEAST its own weight are
## nearer to the player than it is. Past a budget of four it decays toward
## CROWD_MIN — still there, still legible up close, no longer competing.
##
## Wayfinding is exempt: priority 3 is the answer to "what do I do next", and
## the one caption the crowd must never be allowed to quieten.
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

## Priority-aware distance fade. The floor is the point: a wayfinding caption
## stays legible from across the room while a gag drops to a whisper, so a
## static frame shows its own reading order instead of twenty equal captions.
func _by_distance() -> float:
	if not is_instance_valid(_player):
		return 1.0
	var d := _dist
	if d < FADE_NEAR:
		return 1.0
	var a := clampf(1.0 - (d - FADE_NEAR) / 700.0, _floor, 1.0)
	# The cull used to be a step: at _cull - 1 the caption held its 0.18 floor and
	# at _cull + 1 it was gone. A player pacing across that radius made every
	# low-priority gag in the room blink, because the alpha ramp (2.4/s) crosses
	# 0.18 in well under the 0.12s retarget interval. Ramp the last stretch out
	# instead, so the gag dissolves rather than switching off.
	if d > _cull - CULL_RAMP:
		a *= clampf((_cull - d) / CULL_RAMP, 0.0, 1.0)
	return a

## No caption may share pixels with the character. Set dressing yields to the
## player and to the interact prompt over their head, always — first by MOVING,
## and only where it cannot move, by getting out of the frame entirely.
##
## Both rects are taken from the label's HOME and from the dodge TARGET, never
## from where the plate currently sits. Testing the live position against the
## player is a feedback loop: the plate slides clear, the player is no longer
## inside it, the dodge releases, the plate slides back into the player, forever.
##
## Round 6, two changes, both of them defect 1:
##
##  * The player is a BOX now, not a point. `global_position` is at the feet;
##    the sprite is a 32px texture at 2.2x drawn 18px high of centre and the
##    "[E]" prompt floats above that. The old point test only fired when the
##    FEET were inside the plate, so localhost's "talk to Claude first ->"
##    (plate at world y 598..626 against a spawn at y 640) never registered as
##    an overlap at all and printed across the character's head and torso in
##    every localhost frame, dialogue included.
##
##  * A label that cannot move now goes to ZERO, not to 0.30. A headline's
##    accent bar and underlit base carry BLEND_MODE_ADD, and additive ink at
##    0.30 over a dark apartment floor is still bright — the round-5 frame is a
##    yellow bar and a yellow underline burning straight through the sprite with
##    the text ducked underneath them. There is no alpha at which a plate on top
##    of the character is better than no plate; the objective panel and the NPC's
##    own nameplate carry that information anyway, and the caption returns the
##    moment the player takes a step.
func _clear_of_player(vis: float) -> float:
	if not is_instance_valid(_player):
		return vis
	# The plate's HOME in global space (`_home` is parent-local, and the live
	# `position` carries the dodge, the bob and the settle offset), plus the
	# slide the HUD pass has already asked for this tick.
	var ghome := global_position - (position - _home)
	var r := Rect2(ghome + _dodge_to, _size)
	var body := Rect2(_player.global_position + PLAYER_BODY.position, PLAYER_BODY.size)
	if not r.grow(PLAYER_CLEAR + PLAYER_RING).intersects(body):
		return vis
	if not r.grow(PLAYER_CLEAR).intersects(body):
		return minf(vis, 0.62)
	if _bolted or _pinned:
		return 0.0                          # cannot slide (see _bolted / _pinned)
	# Shortest slide that takes the whole plate — plus its clearance — off the
	# whole body, rather than the round-5 nudge that only cleared the feet.
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
	# Did the capped slide actually get clear? If the HUD push and the player
	# were pulling in different directions there may be nothing left to spend,
	# and a caption still on the character at the end of its travel has to fade
	# instead of pretending the move worked.
	if Rect2(ghome + _dodge_to, _size).grow(PLAYER_CLEAR).intersects(body):
		return 0.0
	# It is on its way out. Dim while it travels — the slide is ~0.3s at the
	# dodge rate — so the handover reads as the caption stepping aside.
	return minf(vis, 0.55)

## This label's plate in SCREEN space, taken from its HOME position rather than
## from wherever the dodge currently has it — testing the dodged rect against the
## bands is a feedback loop (push out, no longer overlapping, release, push out
## again). get_global_transform_with_canvas() is the ONLY transform that includes
## the camera; get_viewport_transform() * get_global_transform() leaves the
## canvas out and silently compares world coordinates against screen bands.
func _home_screen_rect(sc: Vector2) -> Rect2:
	var xf := get_global_transform_with_canvas()
	# WorldLabel extends Node2D — there is no `size`. `box` is the plate's real
	# footprint in world space, set at placement time.
	var plate: Vector2 = box.size if box.size != Vector2.ZERO else Vector2(180.0, 40.0)
	var origin := xf.origin - (position - _home) * sc
	return Rect2(origin, plate * sc)

## How far this caption has to move, in WORLD units, to get clear of the HUD's
## reserved bands — and sets `_hud_hide` when no move short enough exists.
##
## The old version only ever hid, and its top band was 48 units too short, which
## is how "OPEN PLAN" ended up printed through "Cycle 1 · reset in 139s" in the
## corporate_enterprise QA frame. Hiding is also the wrong FIRST answer: the
## caption drifting into a 40px band is usually the one you just walked up to
## read. It now slides out of the band, and only gives up when clearing it would
## cost more than PUSH_MAX or when the band it is in has no free side.
##
## Bands: the top bar (resources / region banner / cycle readout / toast lane),
## the bottom ability bar + controls footer, the bottom-left objective panel and
## the bottom-right minimap. Each is max(absolute, fraction-of-viewport) so an
## unusual window aspect — the QA capture runs 1920x928 against a 1080-unit
## design — cannot shrink a band below the HUD it is protecting.
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
	# A boss owns two more bands while it is alive: the announcement card at the
	# top and the status frame above the ability bar. boss_hud.gd braces both
	# with opaque plates, but an opaque plate only stops a caption being READ
	# THROUGH — the cloud_district frame has the health panel sitting on top of
	# "Egress fees apply / on leaving", and the stackoverflow_ruins title card's
	# magenta rule cutting through "Closed: not enough research effort shown".
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
		_hud_hide = true                              # no clear air either way
		_hud_over = 1.0
		return Vector2.ZERO
	var push := Vector2(0.0, down - up)
	# The two bottom corner panels: leaving sideways is usually the shorter trip,
	# so take whichever of "outward" and "up" costs less.
	# Each corner branch KEEPS the vertical clearance the bar bands already asked
	# for. Overwriting it (round 5 did) meant a caption in the bottom-left corner
	# took the sideways exit out of the objective panel and parked itself under
	# the ability bar instead — one reserved band traded for another. The lift
	# exits already subsume the bottom band, since both panel tops sit above it.
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
	# The side edges of the FRAME itself. The two bar bands already run to the
	# top and bottom edges, so vertical slicing is covered; nothing covered the
	# sides, and half a caption hanging off the left of the frame reads as the
	# same clipping bug as half a caption under the ability bar. Applied as a
	# floor/ceiling rather than added, so it cannot compound with the corner
	# panels — the objective column already reaches further in than this margin.
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
	# How much of the plate is really inside a band, as a fraction of its own
	# area. Worst single band, not the union: a plate half in the top bar and
	# half in the minimap does not exist, and summing would double-count the
	# corner panels against the bar band they sit inside.
	_hud_over = maxf(
		maxf(_clip_frac(r, Rect2(0.0, 0.0, view.x, top)),
			_clip_frac(r, Rect2(0.0, bottom, view.x, view.y - bottom))),
		maxf(_clip_frac(r, Rect2(0.0, obj_top, obj_w, view.y - obj_top)),
			_clip_frac(r, Rect2(map_x, map_top, view.x - map_x, view.y - map_top))))
	# The off-frame strips count too, so a BOLTED headline sliced by the side of
	# the frame fades rather than sitting there as half a word — it has no slide
	# to spend and _hud_over is the only thing it yields on.
	_hud_over = maxf(_hud_over, maxf(
		_clip_frac(r, Rect2(-view.x, 0.0, view.x + BAND_EDGE, view.y)),
		_clip_frac(r, Rect2(view.x - BAND_EDGE, 0.0, view.x + BAND_EDGE, view.y))))
	if push.length() > PUSH_MAX:
		# Give up on clearing the band, but keep the slide we DO have instead of
		# snapping home. Returning ZERO here made the plate travel back INTO the
		# HUD over the ~0.3s the fade takes, so the last thing the player saw was
		# the caption walking under the ability bar. Hold at the cap and fade.
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
## read here as "not a boss" — this class does not get to die of a typo again
## (HANDOVER 6b).
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
