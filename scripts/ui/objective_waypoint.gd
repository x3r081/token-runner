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
var _accent := _GameTheme.CYAN

var _t := 0.0
var _resolve_t := 999.0
var _metres := 0
var _compass := ""
var _player_cache: Node2D = null
var _last_label_name := ""
var _last_label_metres := -1
var _last_label_cross := false

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

	_label = Label.new()
	_label.name = "WaypointReadout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_label.clip_text = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_font_override("font", _GameTheme.spaced_font(1))
	_label.add_theme_color_override("font_color", _GameTheme.CYAN_HOT)
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.95))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)

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
	if _label and _label.visible != on:
		_label.visible = on
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
	var label_anchor := Vector2.ZERO

	if inside:
		# On screen: a beacon bobbing above the thing, aimed straight down at it.
		var pos := sp + Vector2(0, -BEACON_LIFT + sin(_t * 2.6) * 6.0)
		# Keep the beacon out of the bands the HUD panels occupy (it is mounted
		# behind them). Clamped, it still sits directly above the target in X and
		# still points down at it, so the read is identical.
		pos.y = clampf(pos.y, MARGIN_TOP, view.y - MARGIN_BOTTOM)
		pos = _avoid_vertical(pos, _ex_quest)
		pos = _avoid_vertical(pos, _ex_radar)
		pos = _avoid_vertical(pos, _ex_toast)
		_marker.position = pos
		_marker.rotation = PI
		label_anchor = _marker.position + Vector2(0.0, -40.0)
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
		label_anchor = _marker.position - d.normalized() * 46.0
	# Hugging the top of the safe box, the readout would land in the status
	# strip's lane — flip it under the chevron instead.
	if label_anchor.y < MARGIN_TOP - 4.0:
		label_anchor = _marker.position + Vector2(0.0, 46.0)
	# Text first, then centre the readout on its anchor using the label's own
	# measured size, so a long target name never drifts off to the right.
	_update_label_text()
	var lp := label_anchor - _label.size * 0.5
	lp.x = clampf(lp.x, 8.0, maxf(view.x - _label.size.x - 8.0, 8.0))
	lp.y = clampf(lp.y, 92.0, maxf(view.y - _label.size.y - 8.0, 92.0))
	_label.position = lp

	var s := (1.0 if inside else 1.22) * (1.0 + 0.08 * pulse)
	_marker.scale = Vector2(s, s)
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
	_label.modulate.a = alpha
	_show(true)

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
	_ring.visible = _cross_region

func _update_label_text() -> void:
	if _target_name == _last_label_name and _metres == _last_label_metres \
			and _cross_region == _last_label_cross:
		return
	_last_label_name = _target_name
	_last_label_metres = _metres
	_last_label_cross = _cross_region
	if _cross_region:
		# The joke rides alongside the information: the second line is the actual
		# instruction, because "24m" toward a wall is not an instruction.
		_label.text = "%s  ·  %dm\nthrough this portal" % [_target_name, _metres]
	elif _target_name == "":
		_label.text = "%dm" % _metres
	elif _metres <= 3:
		_label.text = _target_name
	else:
		_label.text = "%s  ·  %dm" % [_target_name, _metres]
	# Shrink-to-fit: Controls grow to their minimum size but never shrink back on
	# their own, and a stale width would push the readout off-centre.
	_label.size = Vector2.ZERO

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
