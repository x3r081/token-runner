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
##   * distance fade (full near the player, dimmed across the room) plus a
##     proximity duck so a caption never sits on top of the player's own head,
##   * a gentle float, phase-offset per label so they never bob in unison.

# Master palette (docs/VISUAL_BIBLE.md).
const PLATE_BG := Color("#0B0E1C")
const PLATE_LINE := Color("#2A3558")
const WHITE_HOT := Color("#F4F9FF")

## Above every world sprite (props top out near y_max + half ≈ 1050) and above
## the foreground framing (500–601). Deliberately below enemy HP bars (≈ +600
## on the enemy) and the player's own interact prompt, which must never be
## covered by set dressing.
const Z_PLATE := 1150

## Candidate offsets, cheapest displacement first. Vertical nudges come before
## horizontal ones because a sign that slides sideways stops pointing at the
## thing it names.
const LADDER := [
	Vector2(0, 0), Vector2(0, -26), Vector2(0, 26), Vector2(0, -52), Vector2(0, 52),
	Vector2(0, -80), Vector2(0, 80), Vector2(-124, 0), Vector2(124, 0),
	Vector2(-124, -44), Vector2(124, -44), Vector2(-124, 46), Vector2(124, 46),
	Vector2(0, -114), Vector2(0, 114), Vector2(-208, 0), Vector2(208, 0),
	Vector2(-208, -72), Vector2(208, -72), Vector2(0, -152), Vector2(0, 152),
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
static var _add_mat: CanvasItemMaterial

## The label's own footprint in world space, so callers can hang a neon fixture
## or a bracket off the plate instead of guessing where the text ended up.
var box := Rect2()

var _base_y := 0.0
var _center := Vector2.ZERO
var _phase := 0.0
var _t := 0.0
var _tick := 0.0
var _do_bob := true
var _do_fade := true
var _alpha := 1.0
var _target := 1.0
var _player: Node2D = null

# --------------------------------------------------------------- layout -----

## Call once at the top of a region build. `bounds` is the room rect; labels are
## clamped inside it, so a nudge can never push text into a wall or off-world.
static func begin(bounds: Rect2) -> void:
	_claims.clear()
	_prios.clear()
	_owners.clear()
	_bounds = bounds
	_phase_seed = 0.0

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
	var key := str(font_size) + ":" + text
	if _box_cache.has(key):
		return _box_cache[key]
	var size := Vector2.ZERO
	var font: Font = ThemeDB.fallback_font
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

# ----------------------------------------------------------- construction ---

## Build a world label. Returns the node (already parented) — hidden rather than
## overlapping when the room has no space left and this label is expendable.
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

	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_col)
	lbl.add_theme_color_override("font_outline_color", Color(0.004, 0.006, 0.02, 0.95))
	lbl.add_theme_constant_override("outline_size", 3 if want_plate else 5)
	lbl.add_theme_constant_override("line_spacing", 1)
	# Measured from the font, not from the Label: a Control that is not yet in
	# the tree has no resolved theme cache, so its own minimum size can come back
	# as zero. Whichever number is bigger wins, plus a couple of pixels for glyph
	# bearing and the outline — the plate must never be narrower than its text.
	var text_size := measure(text, font_size)
	lbl.reset_size()
	text_size = Vector2(maxf(text_size.x, lbl.size.x) + 4.0, maxf(text_size.y, lbl.size.y) + 2.0)
	lbl.size = text_size

	var pad := PAD if want_plate else Vector2(2.0, 1.0)
	var box_size := text_size + pad * 2.0 + Vector2(bar_w, 0.0)
	var placed := _place(pos, box_size, prio, want_claim)
	var at: Vector2 = placed["pos"]

	var node := WorldLabel.new()
	node.name = "WorldLabel"
	node.position = at
	node.z_index = z
	node.box = Rect2(at, box_size)
	node._base_y = at.y
	node._center = at + box_size * 0.5
	node._do_bob = want_bob
	node._do_fade = want_fade
	_phase_seed += 1.37
	node._phase = _phase_seed
	var slot := int(placed["slot"])
	if slot >= 0 and slot < _owners.size():
		_owners[slot] = node
	parent.add_child(node)

	if want_plate:
		_build_plate(node, box_size, accent, bar_w, headline)
	lbl.position = Vector2(pad.x + bar_w, pad.y)
	node.add_child(lbl)

	if not bool(placed["ok"]):
		# The room genuinely ran out of clear space and this label is expendable.
		# Silence beats two captions sharing pixels.
		node.visible = false
		node.set_process(false)
	elif not want_bob and not want_fade:
		# Printed matter never moves and never fades — it does not need a frame
		# callback for the rest of the region's life.
		node.set_process(false)
	return node

## Glass plate: BASE at ~86%, hairline accent-tinted border, 6px radius, and a
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

# ------------------------------------------------------------- internals ----

## One StyleBoxFlat per accent+weight combo — ~20 labels a region share a
## handful of instances instead of allocating one each (bible: reuse resources
## wherever params are identical).
static func _plate_style(accent: Color, headline: bool) -> StyleBoxFlat:
	var key := accent.to_html(false) + ("H" if headline else "N")
	if _style_cache.has(key):
		return _style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PLATE_BG.r, PLATE_BG.g, PLATE_BG.b, 0.90 if headline else 0.84)
	sb.border_color = Color(
		lerpf(PLATE_LINE.r, accent.r, 0.45),
		lerpf(PLATE_LINE.g, accent.g, 0.45),
		lerpf(PLATE_LINE.b, accent.b, 0.45),
		0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 5
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
## means every candidate collided with something this label may not displace, so
## the caller hides it rather than printing two captions on the same pixels.
static func _place(pos: Vector2, size: Vector2, prio: int, claim: bool) -> Dictionary:
	if not claim:
		return {"pos": pos, "ok": true, "slot": -1}
	for off: Vector2 in LADDER:
		var at := _clamp_in(pos + off, size)
		if _colliders(Rect2(at, size)).is_empty():
			return {"pos": at, "ok": true, "slot": _claim(Rect2(at, size), prio)}
	# Nothing clear anywhere on the ladder. Wayfinding and region names outrank
	# flavour gags: evict the losers from the home spot and take it.
	var home := _clamp_in(pos, size)
	var hit := _colliders(Rect2(home, size))
	for i: int in hit:
		if int(_prios[i]) >= prio:
			return {"pos": home, "ok": false, "slot": -1}
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

static func _claim(r: Rect2, prio: int) -> int:
	_claims.append(r)
	_prios.append(prio)
	_owners.append(null)
	return _claims.size() - 1

## Indices of every claim this box would touch. 4px of air around each plate:
## boxes that merely kiss still read as one smeared block at 1080p.
static func _colliders(r: Rect2) -> Array:
	var out: Array = []
	var grown := r.grow(4.0)
	for i in _claims.size():
		if (_claims[i] as Rect2).intersects(grown):
			out.append(i)
	return out

static func _clamp_in(at: Vector2, size: Vector2) -> Vector2:
	var lo := _bounds.position + Vector2(26.0, 78.0)
	var hi := _bounds.position + _bounds.size - size - Vector2(26.0, 34.0)
	return Vector2(clampf(at.x, lo.x, maxf(lo.x, hi.x)), clampf(at.y, lo.y, maxf(lo.y, hi.y)))

# --------------------------------------------------------------- runtime ----

func _ready() -> void:
	modulate.a = _alpha

## Float + distance fade. No allocations: the alpha target is recomputed at
## ~8Hz, the float is one sin per frame.
func _process(delta: float) -> void:
	_t += delta
	if _do_bob:
		position.y = _base_y + sin(_t * 1.15 + _phase) * 2.0
	# The HUD check runs even for non-fading labels (headline signs opt out of
	# distance fade, but must still yield to an opaque panel).
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.12
		_retarget()
	if not is_equal_approx(_alpha, _target):
		_alpha = move_toward(_alpha, _target, delta * 2.4)
		modulate.a = _alpha

func _retarget() -> void:
	if _under_hud():
		_target = 0.0
		return
	if not _do_fade:
		_target = 1.0
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if not is_instance_valid(_player):
			_target = 1.0
			return
	var d := _player.global_position.distance_to(_center)
	if d < 92.0:
		# Duck: the player is standing IN the caption. Set dressing yields to the
		# character and to the interact prompt over their head, always.
		_target = 0.30
	elif d < 560.0:
		_target = 1.0
	else:
		_target = clampf(1.0 - (d - 560.0) / 700.0, 0.34, 1.0)

## True when this label's plate overlaps a reserved HUD band in SCREEN space.
## Bands: the top bar (resources / region banner / cycle readout / toast lane),
## the bottom ability bar + controls footer, the bottom-left objective panel and
## the bottom-right minimap.
func _under_hud() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	# get_global_transform_with_canvas() is the ONLY one that includes the camera;
	# get_viewport_transform() * get_global_transform() leaves the canvas out and
	# silently compares world coordinates against screen bands.
	var xf := get_global_transform_with_canvas()
	var tl := xf.origin
	# WorldLabel extends Node2D — there is no `size`. `box` is the plate's real
	# footprint in world space, set at placement time.
	var plate: Vector2 = box.size if box.size != Vector2.ZERO else Vector2(180.0, 40.0)
	var br := tl + plate * xf.get_scale()
	var view: Vector2 = vp.get_visible_rect().size
	# Fully off-screen: not a HUD problem, let the distance fade decide.
	if br.x < 0.0 or tl.x > view.x or br.y < 0.0 or tl.y > view.y:
		return false
	if tl.y < 104.0:
		return true                                   # top bar band
	if br.y > view.y - 74.0:
		return true                                   # ability bar / footer band
	if br.x < 400.0 and br.y > view.y - 210.0:
		return true                                   # objective panel
	if tl.x > view.x - 240.0 and br.y > view.y - 220.0:
		return true                                   # minimap
	return false
