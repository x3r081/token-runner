extends Control
## Objective waypoint — the game's standing answer to "what now, and WHERE?".
##
## Quest text can say "Talk to your AI roommate" all it likes; if the player is
## standing in a dark apartment full of glowing rectangles, that sentence is a
## riddle. This node resolves the CURRENT objective (QuestManager.get_current_
## objective) to a live world node and pins a chevron to it: a bobbing beacon
## when the target is on screen, an edge-clamped arrow with a distance readout
## when it is not.
##
## Two visual modes, because they mean different things:
##   IN-REGION   cyan chevron, tight pulse, comet trail. "Walk there."
##   ANOTHER REGION violet chevron inside a slow-turning diamond, and the readout
##                  says which portal and that it is a portal. "Leave first."
##
## Style per VISUAL_BIBLE: WHITE_HOT core (so HDR bloom catches it), gentle
## pulse, dark outline for readability against neon floors. It fades out when you
## are basically standing on the thing, hides during dialogue/modals, keeps clear
## of every HUD panel, and never, ever eats input.
##
## Cost: one group scan every RESOLVE_INTERVAL. Per frame it is a handful of
## transforms and node property writes — no allocations, no redraws.
##
## ROUND 5 — the readout is ONE PLATE
##
## The round-4 QA frames caught this surface at its worst. Over a portal it read
## as a loose three-line stack of glowing text at ~20px leading:
##
##     Localhost  ·  13m          <- this node, line 1
##     through this portal        <- this node, line 2
##     → GPU Mines                <- the PORTAL's own world label, and the
##                                   chevron was drawn straight through the word
##
## Three separate causes, all fixed here:
##
##   1. The readout was a bare Label with a `\n` in it, drawn over whatever the
##      world happened to be doing. It is now a single-line, opaque, bordered
##      PLATE with an accent lip — a UI object with a stated boundary, the same
##      argument boss_hud.gd made about its own bar. Nothing shows through it and
##      nothing reads as belonging to it that does not.
##   2. The plate was offset a fixed 40/46px from the marker CENTRE, so a long
##      destination name printed through its own chevron. It is now offset by
##      the marker's own live outer edge *plus its own half-extent along the
##      offset axis*, measured from its real box — the geometry holds at any
##      text length and at any marker scale.
##   3. The plate could ride up to y=92, i.e. into the status strip and across
##      the boss entrance banner. It is now band-aware: wholly inside the
##      guidance band boss_hud.gd reserves for us (GUIDE_BAND_TOP..BOTTOM) or
##      wholly below it, never straddling its lower edge.
##
## The chevron over-printing the portal's own "→ Destination" label is fixed on
## BOTH sides of the line, and the other side is the one that actually does it:
## `region_portal.gd` moved that label from a local y of -60 (dead centre of this
## node's beacon column) to LABEL_TOP = +64, i.e. under the vortex. `_portal_
## clearance` stays here as a sign-aware guard in case it ever moves back — a
## label at a POSITIVE local y is below the portal and needs no clearance at all.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

## Screen margins the pinned arrow is clamped inside. The top clears the region
## banner + status strip (which end at y=122); the bottom clears the ability bar
## (which starts at view.y-100). Panels that do NOT span the full width — the
## objective panel, the radar, the toast card — are handled as exclusion rects
## instead, so the arrow keeps the whole middle of the frame to work with.
const MARGIN_X := 96.0
const MARGIN_TOP := 138.0
const MARGIN_BOTTOM := 122.0
## Breathing room left around a HUD panel when the marker is pushed off it.
const AVOID_PAD := 14.0
## Group scans are cheap but not free; four times a second is invisible to the
## player and inaudible to the frame budget.
const RESOLVE_INTERVAL := 0.3
## World pixels per "metre". A region is ~1600px across, which reads as a
## believable 50m room rather than "1600 units, good luck".
const PX_PER_METRE := 32.0
## Inside this radius the target is right in front of you; the marker steps
## aside rather than parking itself on the NPC's face.
const NEAR_RADIUS := 130.0
## How high above the target the on-screen beacon floats.
const BEACON_LIFT := 52.0
## Visibility test padding — near the full frame, so anything the player can
## actually see gets a beacon rather than an edge arrow.
const VIEW_PAD_X := 44.0
const VIEW_PAD_TOP := 132.0
const VIEW_PAD_BOTTOM := 96.0
## Comet trail: ghost chevrons chasing the marker, each lagging the one before.
const TRAIL_LEN := 5
const TRAIL_LAG := 0.34

## Plate padding around the readout's own text box. Deliberately tight: the
## whole plate has to fit the guidance band when the chevron is pinned to the
## top edge, and that band (GUIDE_BAND_TOP..BOTTOM) is 74px tall.
const PLATE_PAD_X := 13.0
const PLATE_PAD_Y := 6.0
## The marker's own reach from its centre, at scale 1: the dark outline chevron
## (a 19px point scaled 1.34) and, in cross-region mode, the diamond ring. The
## plate clears whichever of the two is actually drawn, times the marker's LIVE
## scale, plus PLATE_GAP.
##
## Not a flat number, and this matters. A flat 44 was sized for the widest case
## (the pinned cross-region ring, 30 x 1.32 = 40) and then charged to every
## other case as well — which pushed the readout over a plain in-region NPC
## ~19 world px higher than the geometry `npc.gd` measured its NAME_TARGET_LIFT
## against ("objective_waypoint.gd parks its readout ~111 screen px above its
## target"), so the plate clipped the bottom edge of a tracked NPC's lifted
## nameplate at the top of the bob. Scaling the clearance to what is actually on
## screen keeps every case tight and keeps that contract intact.
const CHEVRON_REACH := 25.5
const RING_REACH := 30.0
const PLATE_GAP := 9.0
## The band at the top of the screen that guidance owns, and may not leave.
## Below it: the status strip ends at y=122. Above it: boss_hud.gd starts its
## entrance card at BAND_TOP=222 precisely because this node hangs a readout
## here. A plate that is partly in this band and partly below it is what printed
## a readout across "INC-5441 · SEVERITY: YES" in region_token_vault.png — so
## the plate is either wholly inside the band or wholly below it, never both.
##
## 214 and not 202: boss_hud.gd's own header states the contract as "y 119..214
## belongs to guidance", with its first ink at 226. 202 was the measurement of
## the OLD two-line readout, not the boundary — and using it as the boundary
## made this rule DRAG the plate 11px back up into the chevron it is supposed to
## keep clear of, clipping the cross-region ring's lower tip against an opaque
## box. At 214 the pinned worst case is y 183..214 and the marker clearance
## survives to within a couple of px of the ring's tip.
const GUIDE_BAND_TOP := 140.0
const GUIDE_BAND_BOTTOM := 214.0
## Slack left between a portal's own destination label and the chevron floating
## above it. See `_portal_clearance`.
const PORTAL_LABEL_CLEAR := 46.0
## Screen margin the plate is hard-clamped inside as a last resort.
const PLATE_EDGE_PAD := 12.0

const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Dry consolation prizes for when the quest system has nothing for you.
const IDLE_TARGET_NAME := "Way out"

var _marker: Node2D
var _halo: Sprite2D
var _ring: Polygon2D
var _outline: Polygon2D
var _glow: Polygon2D
var _body: Polygon2D
var _core: Polygon2D
var _plate: Panel
var _plate_style: StyleBoxFlat
var _label: Label
var _trail: Array[Polygon2D] = []

var _target: Node2D = null
var _had_target := false
var _target_name := ""
var _objective: Dictionary = {}
## True when we are pointing at the way out because there is no objective at all.
var _fallback := false
## True when the objective lives in a different region and we are aiming at the
## portal that gets you closer to it.
var _cross_region := false
## True when whatever we resolved to is a region portal — cross-region targets
## and the idle "way out" fallback both are. Portals carry their own world-space
## destination label, which the beacon has to float clear of.
var _target_is_portal := false
var _accent := _GameTheme.CYAN

var _t := 0.0
var _resolve_t := 999.0
var _metres := 0
var _compass := ""
var _player_cache: Node2D = null
var _last_label_name := ""
var _last_label_metres := -1
var _last_label_cross := false
## "through this portal" is only true while you can SEE the portal; pinned at the
## screen edge the same words point at a wall. The on-screen state is therefore
## part of the readout's cache key.
var _last_label_inside := false

## HUD panels the marker must never sit on top of. Recomputed only when the
## viewport size changes, so the per-frame cost is three Rect2 point tests.
var _view_size := Vector2.ZERO
var _ex_quest := Rect2()
var _ex_radar := Rect2()
var _ex_toast := Rect2()

func _ready() -> void:
	name = "ObjectiveWaypoint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	QuestManager.quest_started.connect(_on_quest_signal)
	QuestManager.quest_updated.connect(_on_quest_signal)
	QuestManager.quest_completed.connect(_on_quest_signal)
	GameManager.region_changed.connect(_on_quest_signal)
	# The objective panel resizes itself around its own text, so re-measure the
	# exclusion whenever it does instead of only on a viewport resize (which in
	# a windowed session may never happen after startup).
	var qp := get_parent().get_node_or_null("QuestPanel") if get_parent() else null
	if qp is Control:
		(qp as Control).item_rect_changed.connect(func() -> void:
			_refresh_exclusions(get_viewport_rect().size)
		)
	set_process(true)

## Chevron stack, drawn back to front: comet trail, soft halo, cross-region ring,
## dark outline, additive glow, accent body, white-hot core. Overbright colors
## (>1.0) push the core and glow into HDR so the bloom pass makes the arrow read
## from across the room.
func _build() -> void:
	_marker = Node2D.new()
	_marker.name = "Marker"
	_marker.visible = false
	add_child(_marker)

	# Points "up" (-Y) at rotation 0; rotation aims it at the target.
	var pts := PackedVector2Array([
		Vector2(0, -19), Vector2(14, 12), Vector2(0, 4), Vector2(-14, 12),
	])
	# Trail ghosts are siblings of the marker (own positions, own lag) and are
	# moved behind it so the head of the comet stays the brightest thing.
	for i in TRAIL_LEN:
		var g := Polygon2D.new()
		g.polygon = pts
		g.material = FxLib.additive_material()
		g.visible = false
		var k := 1.0 - float(i) / float(TRAIL_LEN)
		g.scale = Vector2.ONE * (0.86 * k + 0.14)
		g.color = Color(_accent.r, _accent.g, _accent.b, 0.20 * k)
		add_child(g)
		move_child(g, 0)
		_trail.append(g)

	_halo = Sprite2D.new()
	_halo.texture = FxLib.light_texture()
	_halo.material = FxLib.additive_material()
	_halo.modulate = Color(_GameTheme.CYAN.r * 0.9, _GameTheme.CYAN.g * 0.9, _GameTheme.CYAN.b * 0.9, 0.5)
	var halo_w := maxf(1.0, float(_halo.texture.get_width()))
	_halo.scale = Vector2.ONE * (86.0 / halo_w)
	_marker.add_child(_halo)

	# Cross-region badge: a slow-turning diamond that only appears when the
	# objective is behind a portal. You read "different mode" before you read
	# the label.
	_ring = Polygon2D.new()
	_ring.polygon = PackedVector2Array([
		Vector2(0, -30), Vector2(30, 0), Vector2(0, 30), Vector2(-30, 0),
	])
	_ring.color = Color(_GameTheme.VIOLET.r, _GameTheme.VIOLET.g, _GameTheme.VIOLET.b, 0.0)
	_ring.material = FxLib.additive_material()
	_ring.visible = false
	_marker.add_child(_ring)

	_outline = _add_chevron(pts, Color(_GameTheme.VOID.r, _GameTheme.VOID.g, _GameTheme.VOID.b, 0.9), 1.34)
	_glow = _add_chevron(pts, Color(_GameTheme.CYAN.r, _GameTheme.CYAN.g, _GameTheme.CYAN.b, 0.45), 1.62)
	_glow.material = FxLib.additive_material()
	_body = _add_chevron(pts, Color(_GameTheme.CYAN.r * 1.5, _GameTheme.CYAN.g * 1.5, _GameTheme.CYAN.b * 1.5, 1.0), 1.0)
	_core = _add_chevron(pts, _GameTheme.WHITE_HOT, 0.46)
	_core.position = Vector2(0, -3)

	# The readout plate. Added AFTER the marker so it draws in front of the
	# chevron's additive halo — an opaque box with soft glow behind it reads as
	# one object, which is the entire point of consolidating the stack.
	_plate = Panel.new()
	_plate.name = "WaypointPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.visible = false
	_plate_style = _make_plate_style()
	_plate.add_theme_stylebox_override("panel", _plate_style)
	add_child(_plate)

	_label = Label.new()
	_label.name = "WaypointReadout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.clip_text = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_font_override("font", _GameTheme.spaced_font(1))
	_label.add_theme_color_override("font_color", _GameTheme.CYAN_HOT)
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.95))
	# 5px of outline was compensating for having no plate behind the text. With
	# an opaque plate it just fattens the glyphs; 3 keeps the crispness and still
	# survives the accent lip.
	_label.add_theme_constant_override("outline_size", 3)
	_plate.add_child(_label)

## VISUAL_BIBLE UI tokens (BASE bg, 1px LINE border, radius 6) with two
## deliberate departures: the background is opaque, not 92% — this plate lands on
## portal vortexes and gold vault floors and must never let them through — and
## the left border is a 3px accent lip so the plate reads as guidance at a glance
## before a single word of it is read.
func _make_plate_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(_GameTheme.BASE.r, _GameTheme.BASE.g, _GameTheme.BASE.b, 1.0)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.border_color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.85)
	s.set_corner_radius_all(6)
	# Dark accent-tinted halo: separation from a bright floor without adding a
	# second glowing thing next to the chevron's own.
	s.shadow_color = _GameTheme.with_alpha(_GameTheme.CYAN.lerp(_GameTheme.VOID, 0.7), 0.55)
	s.shadow_size = 9
	return s

func _add_chevron(pts: PackedVector2Array, col: Color, sc: float) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	p.scale = Vector2(sc, sc)
	_marker.add_child(p)
	return p

# ------------------------------------------------------------------ signals --
## Any quest/region change invalidates the cached node. Resolving is deferred to
## the next frame on purpose: on region_changed the world has not rebuilt yet
## (the HUD's handler runs before the world's), so scanning now would find the
## corpses of the old region.
func _on_quest_signal(_a = null, _b = null) -> void:
	_resolve_t = RESOLVE_INTERVAL

## Public: force an immediate re-resolve (the HUD calls this on demand).
func refresh_now() -> void:
	_resolve()

# ------------------------------------------------------------------- process --
func _process(delta: float) -> void:
	_t += delta
	_resolve_t += delta
	# A target that vanished under us (a token collected, an enemy dissolved)
	# re-resolves on the spot; having no target at all just waits for the timer,
	# so an empty region doesn't turn into a group scan every frame.
	var lost := _had_target and not is_instance_valid(_target)
	if _resolve_t >= RESOLVE_INTERVAL or lost:
		_resolve()
	if not is_instance_valid(_target):
		_show(false)
		return
	_measure()
	if _should_hide():
		_show(false)
		return
	_place()
	_drag_trail()

## Distance/compass are kept current even while the marker is hidden, so the
## quest tracker is already correct the instant a modal closes.
func _measure() -> void:
	var p := _player()
	if not is_instance_valid(p):
		_metres = 0
		_compass = ""
		return
	var delta := _target.global_position - p.global_position
	_metres = int(round(delta.length() / PX_PER_METRE))
	_compass = _compass_of(delta)

func _should_hide() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return true
	if DialogueManager.is_active or EventManager.has_active_event():
		return true
	if UIManager.has_blocking_ui():
		return true
	return false

func _show(on: bool) -> void:
	if _marker and _marker.visible != on:
		_marker.visible = on
	# The readout's visibility lives on the plate; the Label inside it is always
	# visible and rides along.
	if _plate and _plate.visible != on:
		_plate.visible = on
	for g in _trail:
		if g.visible != on:
			g.visible = on
			if on:
				g.position = _marker.position

## Panel-safe boxes, in screen space. Mirrors hud.gd's layout lanes; recomputed
## only when the window size actually changes.
func _refresh_exclusions(view: Vector2) -> void:
	_view_size = view
	# Objective panel, bottom-left (hud.tscn QuestPanel). Measured from the live
	# node when it exists — the panel grows with its own text, and the hardcoded
	# 208px height was 16px short of what it actually lays out to at 1080p,
	# which let the chevron park inside its bottom edge.
	_ex_quest = Rect2(24.0, view.y - 232.0, 410.0, 208.0)
	var qp := get_parent().get_node_or_null("QuestPanel") if get_parent() else null
	if qp is Control and (qp as Control).visible:
		var r: Rect2 = (qp as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0:
			_ex_quest = r
	# Radar disc, bottom-right (hud.gd Minimap).
	_ex_radar = Rect2(view.x - 220.0, view.y - 220.0, 196.0, 196.0)
	# Toast rail, top-right (hud.gd ToastLane).
	_ex_toast = Rect2(view.x - 396.0, 100.0, 372.0, 66.0)

## Slides a point out of a panel box along its shortest escape route.
func _push_out(p: Vector2, r: Rect2) -> Vector2:
	if not r.grow(AVOID_PAD).has_point(p):
		return p
	var up := p.y - (r.position.y - AVOID_PAD)
	var down := (r.end.y + AVOID_PAD) - p.y
	var left := p.x - (r.position.x - AVOID_PAD)
	var right := (r.end.x + AVOID_PAD) - p.x
	var m := minf(minf(up, down), minf(left, right))
	if m == up:
		p.y = r.position.y - AVOID_PAD
	elif m == down:
		p.y = r.end.y + AVOID_PAD
	elif m == left:
		p.x = r.position.x - AVOID_PAD
	else:
		p.x = r.end.x + AVOID_PAD
	return p

## Two passes: escaping one panel can drop you onto its neighbour.
func _avoid(p: Vector2) -> Vector2:
	for _i in 2:
		p = _push_out(p, _ex_quest)
		p = _push_out(p, _ex_radar)
		p = _push_out(p, _ex_toast)
	return p

## The on-screen beacon only ever moves vertically: it must stay directly above
## its target in X or it stops meaning "this thing here".
func _avoid_vertical(p: Vector2, r: Rect2) -> Vector2:
	if not r.grow(AVOID_PAD).has_point(p):
		return p
	var up := p.y - (r.position.y - AVOID_PAD)
	var down := (r.end.y + AVOID_PAD) - p.y
	p.y = (r.position.y - AVOID_PAD) if up <= down else (r.end.y + AVOID_PAD)
	return p

func _place() -> void:
	var vp := get_viewport()
	if vp == null:
		_show(false)
		return
	var view := get_viewport_rect().size
	if view != _view_size:
		_refresh_exclusions(view)
	var sp: Vector2 = vp.get_canvas_transform() * (_target.global_position + Vector2(0, -14))
	var rect_pos := Vector2(MARGIN_X, MARGIN_TOP)
	var rect_size := Vector2(
		maxf(view.x - MARGIN_X * 2.0, 96.0),
		maxf(view.y - MARGIN_TOP - MARGIN_BOTTOM, 96.0)
	)
	# Two boxes on purpose: "is it visible" is judged against nearly the whole
	# frame, while the pinned arrow is clamped to the tighter panel-safe box.
	# One box for both would flip perfectly visible floor-level tokens into
	# edge-arrow mode just because they sit low on screen.
	var inside := Rect2(
		Vector2(VIEW_PAD_X, VIEW_PAD_TOP),
		Vector2(maxf(view.x - VIEW_PAD_X * 2.0, 64.0), maxf(view.y - VIEW_PAD_TOP - VIEW_PAD_BOTTOM, 64.0))
	).has_point(sp)
	var pulse := 0.5 + 0.5 * sin(_t * 4.2)
	# Text — and therefore the plate's real box — before any geometry: every
	# offset below is computed from the plate's measured size, which is what makes
	# the layout hold for "Open Source Wildlands" as well as for "Tokens".
	_update_label_text(inside)
	# Which side of the chevron the plate hangs off. Straight up when the beacon
	# sits over its target; back toward the screen centre when it is pinned.
	var plate_dir := Vector2.UP
	# The plate hangs off the beacon's RESTING height, never its bobbing one:
	# text that breathes is harder to read, and an oscillating plate edge re-opens
	# every clearance argument twice a second instead of settling it once.
	var plate_anchor := Vector2.ZERO

	if inside:
		# On screen: a beacon bobbing above the thing, aimed straight down at it.
		var lift := BEACON_LIFT
		if _target_is_portal:
			lift = maxf(lift, _portal_clearance(vp))
		var bob := sin(_t * 2.6) * 6.0
		var pos := sp + Vector2(0, -lift + bob)
		# Keep the beacon out of the bands the HUD panels occupy (it is mounted
		# behind them). Clamped, it still sits directly above the target in X and
		# still points down at it, so the read is identical.
		pos.y = clampf(pos.y, MARGIN_TOP, view.y - MARGIN_BOTTOM)
		pos = _avoid_vertical(pos, _ex_quest)
		pos = _avoid_vertical(pos, _ex_radar)
		pos = _avoid_vertical(pos, _ex_toast)
		_marker.position = pos
		_marker.rotation = PI
		plate_anchor = Vector2(pos.x, pos.y - bob)
	else:
		# Off screen: clamp to the margin box, angled along the line to the target.
		var half := rect_size * 0.5
		var centre := rect_pos + half
		var d := sp - centre
		if absf(d.x) < 0.01 and absf(d.y) < 0.01:
			d = Vector2(0, -1)
		var k := minf(half.x / maxf(absf(d.x), 0.01), half.y / maxf(absf(d.y), 0.01))
		_marker.position = _avoid(centre + d * k)
		_marker.rotation = d.angle() + PI * 0.5
		# Readout tucked back toward the screen centre so it never clips off-frame.
		plate_dir = -d.normalized()
		plate_anchor = _marker.position

	# Scale first, because the plate's clearance is measured off the marker's
	# LIVE outer edge rather than a flat number (see CHEVRON_REACH).
	var s := (1.0 if inside else 1.22) * (1.0 + 0.08 * pulse)
	_marker.scale = Vector2(s, s)
	var reach := (RING_REACH if _cross_region else CHEVRON_REACH) * s
	_place_plate(plate_anchor, plate_dir, view, reach + PLATE_GAP)
	# The core breathes between hot-white and nuclear so the bloom pulses too.
	var k_hot := 1.5 + 0.7 * pulse
	_core.color = Color(_GameTheme.WHITE_HOT.r * k_hot, _GameTheme.WHITE_HOT.g * k_hot, _GameTheme.WHITE_HOT.b * k_hot, 1.0)
	_halo.modulate.a = 0.34 + 0.22 * pulse
	if _cross_region:
		# Slow counter-turn against the chevron: unmistakably a different state.
		_ring.rotation = -_marker.rotation + _t * 0.7
		_ring.color = Color(_accent.r * 1.4, _accent.g * 1.4, _accent.b * 1.4, 0.16 + 0.12 * pulse)
		_ring.scale = Vector2.ONE * (1.0 + 0.06 * pulse)

	var alpha := 1.0
	var p := _player()
	if is_instance_valid(p):
		var dist := p.global_position.distance_to(_target.global_position)
		if dist < NEAR_RADIUS:
			# You're on top of it. Back off — the prop's own [E] prompt takes over.
			alpha = lerpf(0.16, 1.0, clampf(dist / NEAR_RADIUS, 0.0, 1.0))
	if _fallback:
		alpha *= 0.62
	_marker.modulate.a = alpha
	_plate.modulate.a = alpha
	_show(true)

## The plate hangs off `anchor` along `dir`, offset by `clear` PLUS its own
## half-extent on that axis. The old code offset a bare Label by a flat 46px from
## the marker CENTRE, which is why a wide readout printed straight through its
## own chevron: half of a 400px-wide box is 200px, and 46 does not cover it.
##
## `anchor` is the marker's RESTING position, not its live one — see `_place`.
func _place_plate(anchor: Vector2, dir: Vector2, view: Vector2, clear: float) -> void:
	var s := _plate.size
	var along := absf(dir.x) * s.x * 0.5 + absf(dir.y) * s.y * 0.5
	var p := anchor + dir * (clear + along) - s * 0.5
	# Hugging the top of the safe box there is no room above the chevron. Move
	# the plate BESIDE it, toward the screen centre — never underneath it. Under
	# an on-screen beacon is precisely where the thing it points AT is standing,
	# and this plate is opaque now: flipping down parks a solid box on the NPC,
	# portal or token the player is being sent to, which is the one object on
	# screen guidance may not hide. Sideways keeps the plate attached to its
	# marker, inside the band, and off the target.
	if dir.y < 0.0 and p.y < GUIDE_BAND_TOP:
		var side := -1.0 if anchor.x > view.x * 0.5 else 1.0
		p = anchor + Vector2(side * (clear + s.x * 0.5), 0.0) - s * 0.5
	# Wholly inside the guidance band, or wholly below it. Straddling its lower
	# edge is what dropped a readout onto the boss entrance banner.
	if p.y < GUIDE_BAND_BOTTOM:
		p.y = clampf(p.y, GUIDE_BAND_TOP, maxf(GUIDE_BAND_BOTTOM - s.y, GUIDE_BAND_TOP))
	# Then off the HUD panels — losing the toast rail matters more than the boss
	# card's 2.2s band, so this runs after the band rule and wins ties.
	var c := p + s * 0.5
	for _i in 2:
		c = _push_rect_out(c, s, _ex_quest)
		c = _push_rect_out(c, s, _ex_radar)
		c = _push_rect_out(c, s, _ex_toast)
	p = c - s * 0.5
	p.x = clampf(p.x, PLATE_EDGE_PAD, maxf(view.x - s.x - PLATE_EDGE_PAD, PLATE_EDGE_PAD))
	# The floor is MARGIN_BOTTOM, not the screen edge: below it live the ability
	# bar and the hint bar, and a last-resort clamp must not be the one thing
	# that drops an opaque plate onto the player's own hotkeys.
	p.y = clampf(p.y, GUIDE_BAND_TOP, maxf(view.y - MARGIN_BOTTOM - s.y, GUIDE_BAND_TOP))
	# Whole pixels: a half-pixel plate origin softens the text on it.
	_plate.position = p.round()

## Rect-vs-rect version of `_push_out`: the plate is a box, not a point, so it
## has to escape a panel by its own half-extent or it leaves a corner behind.
func _push_rect_out(c: Vector2, s: Vector2, r: Rect2) -> Vector2:
	var g := r.grow(AVOID_PAD)
	if not g.intersects(Rect2(c - s * 0.5, s)):
		return c
	var up := c.y - (g.position.y - s.y * 0.5)
	var down := (g.end.y + s.y * 0.5) - c.y
	var left := c.x - (g.position.x - s.x * 0.5)
	var right := (g.end.x + s.x * 0.5) - c.x
	var m := minf(minf(up, down), minf(left, right))
	if m == up:
		c.y = g.position.y - s.y * 0.5
	elif m == down:
		c.y = g.end.y + s.y * 0.5
	elif m == left:
		c.x = g.position.x - s.x * 0.5
	else:
		c.x = g.end.x + s.x * 0.5
	return c

## How far above a PORTAL's screen position the beacon has to float to clear the
## portal's own destination label — a GUARD, and usually a no-op.
##
## The round-4 frames printed "→ GP[chevron]Mines" because the portal's Label
## sat at a local y of -60, dead centre of this node's beacon column. That is
## fixed where it belongs: `region_portal.gd` now sets `label.offset_top =
## LABEL_TOP` = +64, under the vortex, out of the column entirely.
##
## SIGN MATTERS, and getting it wrong is not cosmetic. An earlier draft of this
## function took `absf()` of the label's local y, which reads the label's new
## position BELOW the portal as if it were 64px ABOVE it and floats the beacon
## 64*zoom + 46 ≈ 130px up instead of 52 — the chevron detaches from its own
## portal and the plate is shoved ~200px above the gate, into the band the world
## captions occupy. So: a label at or below the portal's origin needs no
## clearance, full stop, and only a label genuinely above it buys any lift.
##
## Measured off the live node rather than hardcoded, so if the portal scene ever
## moves its text back overhead the beacon follows it without another round.
func _portal_clearance(vp: Viewport) -> float:
	var lab := _target.get_node_or_null("Label")
	if not (lab is Control):
		return BEACON_LIFT
	# Local y of the label's TOP edge. Positive = below the portal centre, which
	# is where it lives now — nothing to clear.
	var top: float = (lab as Control).get_rect().position.y
	if top > -1.0:
		return BEACON_LIFT
	var zoom: float = absf(vp.get_canvas_transform().get_scale().y)
	if zoom < 0.01:
		zoom = 1.0
	return -top * zoom + PORTAL_LABEL_CLEAR

## Chain-lag comet: each ghost chases the one in front of it, so the trail bends
## through the corners instead of snapping. Position writes only — no redraws.
func _drag_trail() -> void:
	var lead := _marker.position
	var lead_rot := _marker.rotation
	var a := _marker.modulate.a
	for i in _trail.size():
		var g: Polygon2D = _trail[i]
		g.position = g.position.lerp(lead, TRAIL_LAG)
		g.rotation = lerp_angle(g.rotation, lead_rot, TRAIL_LAG)
		var k := 1.0 - float(i) / float(TRAIL_LEN)
		g.color = Color(_accent.r * 1.2, _accent.g * 1.2, _accent.b * 1.2, 0.22 * k * a)
		g.scale = _marker.scale * (0.82 * k + 0.12)
		lead = g.position
		lead_rot = g.rotation

## Repaints the chevron stack in the current mode's accent. Called on resolve
## only, never per frame.
func _apply_accent() -> void:
	_glow.color = Color(_accent.r, _accent.g, _accent.b, 0.45)
	_body.color = Color(_accent.r * 1.5, _accent.g * 1.5, _accent.b * 1.5, 1.0)
	_halo.modulate = Color(_accent.r * 0.9, _accent.g * 0.9, _accent.b * 0.9, 0.5)
	_label.add_theme_color_override("font_color", _GameTheme.hot_of(_accent))
	if _plate_style != null:
		_plate_style.border_color = _GameTheme.with_alpha(_accent, 0.85)
		_plate_style.shadow_color = _GameTheme.with_alpha(_accent.lerp(_GameTheme.VOID, 0.7), 0.55)
	_ring.visible = _cross_region

## ONE line, always. The readout used to wrap onto a second line for the
## cross-region case, and stacked next to the portal's own label that made three
## lines of loose glowing text over one piece of art. Everything the design law
## requires — where you are headed, how far, and the physical action — fits on a
## single line, and one line is what lets the plate fit the guidance band.
##
## `on_screen` matters: "through this portal" is an instruction only while the
## portal is in frame. Pinned at the screen edge those words point at a wall, so
## the phrasing switches to the direction the chevron is already giving.
func _update_label_text(on_screen: bool) -> void:
	if _target_name == _last_label_name and _metres == _last_label_metres \
			and _cross_region == _last_label_cross and on_screen == _last_label_inside:
		return
	_last_label_name = _target_name
	_last_label_metres = _metres
	_last_label_cross = _cross_region
	_last_label_inside = on_screen
	if _cross_region:
		# The joke rides alongside the information: the tail is the actual
		# instruction, because "24m" toward a wall is not an instruction.
		if on_screen:
			_label.text = "%s  ·  %dm  ·  through this portal" % [_target_name, _metres]
		else:
			# Not "portal is this way" — that is a statement about the map, and
			# the design law asks for an action the player can name. The chevron
			# supplies the direction; the words supply the verb.
			_label.text = "%s  ·  %dm  ·  head for the portal" % [_target_name, _metres]
	elif _target_name == "":
		_label.text = "%dm" % _metres
	elif _metres <= 3:
		_label.text = _target_name
	else:
		_label.text = "%s  ·  %dm" % [_target_name, _metres]
	_measure_plate()

## Shrink-to-fit, for the plate as well as the text: Controls grow to their
## minimum size but never shrink back on their own, and a stale width would drag
## the plate off-centre and re-open the "readout sits on its own chevron" bug.
func _measure_plate() -> void:
	_label.size = Vector2.ZERO
	var ls := _label.get_combined_minimum_size()
	_label.size = ls
	_label.position = Vector2(PLATE_PAD_X, PLATE_PAD_Y)
	_plate.size = ls + Vector2(PLATE_PAD_X, PLATE_PAD_Y) * 2.0

# ------------------------------------------------------------------ resolve --
func _resolve() -> void:
	_resolve_t = 0.0
	var previous := _target_name
	var prev_cross := _cross_region
	_target = null
	_fallback = false
	_cross_region = false
	_target_name = ""
	_objective = QuestManager.get_current_objective()
	if _objective.is_empty():
		_resolve_fallback()
		_finish_resolve(previous, prev_cross)
		return
	var region := str(_objective.get("region", ""))
	var here: String = GameManager.current_region
	if region != "" and region != here:
		# The objective lives somewhere else: point at the door, not the void.
		_target = _portal_toward(region)
		_target_name = QuestManager.pretty_name(region)
		_cross_region = _target != null
	else:
		var node_id := str(_objective.get("node_id", ""))
		match str(_objective.get("kind", "")):
			"npc":
				_target = _find_npc(node_id)
				_target_name = QuestManager.npc_short_name(node_id)
			"token":
				_target = _nearest_token(node_id)
				_target_name = "Tokens"
			"enemy":
				_target = _nearest_enemy(node_id)
				_target_name = QuestManager.pretty_name(node_id)
			"prop":
				_target = _find_prop(node_id)
				_target_name = _prop_name(_target, node_id)
			"region":
				_target = _portal_toward(node_id)
				_target_name = QuestManager.pretty_name(node_id)
				_cross_region = _target != null
	if _target == null:
		_resolve_fallback()
	_finish_resolve(previous, prev_cross)

func _finish_resolve(previous: String, prev_cross: bool) -> void:
	_had_target = _target != null
	# Portals — cross-region targets and the idle "way out" alike — carry their
	# own world label, so the beacon has to be lifted above it. Property probe
	# rather than a class check: `target_region` is exactly what `_portals()`
	# already identifies a portal by, so the two can never disagree.
	_target_is_portal = is_instance_valid(_target) and "target_region" in _target
	if previous != _target_name or prev_cross != _cross_region:
		_last_label_metres = -1
	var want := _GameTheme.CYAN
	if _cross_region:
		want = _GameTheme.VIOLET
	elif _fallback:
		want = _GameTheme.BLUE
	if want != _accent:
		_accent = want
	_apply_accent()

## No objective (or the objective's target isn't in this region): point at the
## forward portal so the player always has a direction of travel. Dimmed, so it
## reads as "this way, probably" rather than "GO HERE NOW".
func _resolve_fallback() -> void:
	var p := _forward_portal()
	if p == null:
		_target = null
		_target_name = ""
		return
	_target = p
	_fallback = true
	_cross_region = false
	_target_name = IDLE_TARGET_NAME

func _player() -> Node2D:
	if is_instance_valid(_player_cache):
		return _player_cache
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D:
		_player_cache = p as Node2D
	else:
		_player_cache = null
	return _player_cache

func _find_npc(npc_id: String) -> Node2D:
	if npc_id == "":
		return null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and "npc_id" in n and str(n.npc_id) == npc_id:
			return n as Node2D
	return null

func _find_prop(prop_id: String) -> Node2D:
	if prop_id == "":
		return null
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node2D):
			continue
		if "npc_id" in n:
			continue  # NPCs mirror their id into interact_id; not a prop
		if "interact_id" in n and str(n.interact_id) == prop_id:
			return n as Node2D
	return null

## Nearest uncollected token, preferring the type the objective asked for. Falls
## back to any token when the region doesn't stock that flavour.
func _nearest_token(kind: String) -> Node2D:
	var origin := Vector2.ZERO
	var p := _player()
	if is_instance_valid(p):
		origin = p.global_position
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("token"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if "collected" in n and n.collected:
			continue
		if kind != "" and kind != "any" and "token_type" in n and str(n.token_type) != kind:
			continue
		var d: float = origin.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	if best == null and kind != "" and kind != "any":
		return _nearest_token("any")
	return best

## Nearest live enemy of the requested type; any enemy if that type isn't here.
func _nearest_enemy(kind: String) -> Node2D:
	var origin := Vector2.ZERO
	var p := _player()
	if is_instance_valid(p):
		origin = p.global_position
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if kind != "" and kind != "any" and "enemy_type" in n and str(n.enemy_type) != kind:
			continue
		var d: float = origin.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	if best == null and kind != "" and kind != "any":
		return _nearest_enemy("any")
	return best

func _portals() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and "target_region" in n:
			out.append(n as Node2D)
	return out

## The portal that gets you closest to `region_id`. Exact match wins; otherwise
## the one whose destination sits nearest the goal in REGION_ORDER, which on a
## linear map is simply "the door pointing the right way".
func _portal_toward(region_id: String) -> Node2D:
	var portals := _portals()
	if portals.is_empty():
		return null
	var want: int = GameManager.REGION_ORDER.find(region_id)
	var best: Node2D = null
	var best_score := 99999
	for p in portals:
		var dest := str(p.target_region)
		if dest == region_id:
			return p
		var idx: int = GameManager.REGION_ORDER.find(dest)
		var score := 9999
		if idx >= 0 and want >= 0:
			score = absi(idx - want)
		if score < best_score:
			best_score = score
			best = p
	return best

## Progression-flavoured default: the portal leading DEEPER into the game.
func _forward_portal() -> Node2D:
	var portals := _portals()
	if portals.is_empty():
		return null
	var here: int = GameManager.REGION_ORDER.find(GameManager.current_region)
	var best: Node2D = null
	var best_idx := -1
	for p in portals:
		var idx: int = GameManager.REGION_ORDER.find(str(p.target_region))
		if idx > here and (best == null or idx < best_idx):
			best = p
			best_idx = idx
	if best == null:
		best = portals[0]
	return best

func _prop_name(node: Node2D, fallback_id: String) -> String:
	if is_instance_valid(node) and "interact_text" in node:
		var t := str(node.interact_text)
		if t != "" and t != "Interact":
			return t
	return QuestManager.pretty_name(fallback_id)

## Screen/world Y grows downward, so north is -Y. Returns "" for a zero vector.
func _compass_of(dir: Vector2) -> String:
	if dir.length_squared() < 1.0:
		return ""
	var a := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
	return str(COMPASS[int(round(a / 45.0)) % 8])

# -------------------------------------------------------------- public API ---
func has_target() -> bool:
	return is_instance_valid(_target)

## True when we're pointing at the exit because nothing else was tracked.
func is_fallback() -> bool:
	return _fallback

## True when the objective is in another region and this is the portal to it.
func is_cross_region() -> bool:
	return _cross_region

## World position of whatever we are pointing at (the radar plots this).
func target_position() -> Vector2:
	if is_instance_valid(_target):
		return _target.global_position
	return Vector2.ZERO

func target_display_name() -> String:
	return _target_name

func distance_metres() -> int:
	return _metres

func compass() -> String:
	return _compass

## "28m · NE" for the quest tracker, or "" when there's nothing to say.
func readout() -> String:
	if not is_instance_valid(_target):
		return ""
	if _compass == "":
		return "%dm" % _metres
	return "%dm · %s" % [_metres, _compass]
