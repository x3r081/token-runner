extends Control
## Objective waypoint — the game's standing answer to "what now, and WHERE?".
##
## Quest text can say "Talk to your AI roommate" all it likes; if the player is
## standing in a dark apartment full of glowing rectangles, that sentence is a
## riddle. This node resolves the CURRENT objective (QuestManager.get_current_
## objective) to a live world node and points a chevron at it: a bobbing beacon
## when the target is on screen, an edge-clamped arrow with a distance readout
## when it is not.
##
## ROUND 6 — QUIETER, NOT WEAKER. This is the most valued thing on the screen and
## it was also the loudest: a five-ghost comet trail, an 86px additive halo, an
## overbright WHITE_HOT core breathing into the bloom pass, a slow-turning violet
## diamond for the cross-region case, and an opaque bordered plate with a 3px
## accent lip and a 9px shadow under a line of CYAN_HOT text. Seven layers to say
## "over there".
##
## What it is now: ONE chevron in the region's accent over a dark 1px-equivalent
## outline, pulsing 0.9 -> 1.0, and one small line of TEXT_DIM with a one-pixel
## shadow, held clear of the chevron. No halo, no trail, no ring, no plate, no
## overbright, and only ONE of the two elements is coloured.
##
## ROUND 7 — THE BEACON CLEARS WHAT IT POINTS AT. Round 6 floated it a flat 52
## screen px above the target's ORIGIN, which is fine for a token and wrong for
## anything with a body: a portal's mouth reaches further than that in every
## direction, so region_production.png and region_corporate_enterprise.png show
## the chevron sitting ON the swirl, across the portal's own "→ GPU Mines" text.
## `_portal_clearance` and `_npc_clearance` now measure the target's real top
## edge off the live node and float the beacon above THAT.
##
## ROUND 11 — A FROZEN MARKER IS A LYING MARKER, and the arrow is pixel art.
##
## Two defects, both visible in round 10's captures:
##
##   1. THE CHEVRON INSIDE THE PORTAL (production, corporate_enterprise). Round
##      7's clearance arithmetic is not what failed — measure the other eight
##      frames and the beacon sits exactly where it should, a comfortable margin
##      above the swirl. What failed is that in THOSE TWO ROOMS this node had
##      stopped running. Both fire a scripted event on arrival (world.gd
##      `_trigger_production_incident` / `_trigger_all_hands_demo`), the event
##      takes the tree, and a PAUSABLE `_process` that never ticks leaves the
##      marker VISIBLE at the coordinates of the room you just left: production
##      prints GPU Mines' chevron, corporate prints the Wildlands' one, each
##      landing by coincidence inside the new room's portal. Two changes close
##      it — `PROCESS_MODE_ALWAYS`, so `_should_hide()` can always run and hide
##      the marker while something else owns the screen; and `_on_region_change`,
##      which drops the target outright so a frozen frame can only ever show
##      NOTHING rather than the wrong thing. The clearance is now also measured
##      off the chevron's own TIP rather than its centre, so "never on the disc"
##      is a geometric guarantee and not a margin that happens to be big enough.
##   2. THE ROTATED ARROW (token_vault). The pinned marker was a polygon spun to
##      an arbitrary angle, rasterised through the UI fit as a smooth-edged
##      triangle — the one anti-aliased object in a frame that is otherwise a
##      strict pixel grid (LAW 1), and the critic named it as such. It now snaps
##      to one of EIGHT directions and is REBUILT rather than rotated: the points
##      are rotated by a whole octant and rounded to whole units, and
##      `_marker.rotation` stays 0 for the life of the node. The pulse moved from
##      scale to opacity for the same reason — a chevron scaled by 0.94 has
##      fractional vertices, which is the other way to grow soft edges.
##
## Everything else STRUCTURAL is untouched, because all of it was load-bearing:
##   * the on-screen / off-screen split and the edge-pin geometry
##   * the panel exclusion rects, so the marker never parks on a readout
##   * the guidance band rule, so a readout never straddles the boss band
##   * every resolve path and every public method
##
## Cost: one group scan every RESOLVE_INTERVAL. Per frame it is a handful of
## transforms and property writes — no allocations, no redraws.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

## Screen margins the pinned arrow is clamped inside. The top clears the strip
## (region name + cycle line end at ~y 96); the bottom clears the ability bar
## and the key legend. Panels that do NOT span the full width — the objective
## line, the toast lane — are handled as exclusion rects instead, so the arrow
## keeps the whole middle of the frame to work with.
const MARGIN_X := 96.0
const MARGIN_TOP := 112.0
const MARGIN_BOTTOM := 96.0
## The toast lane, mirrored from hud.gd (TOAST_BOTTOM -126, TOAST_H 26,
## TOAST_W 720) as a distance UP from the bottom edge. Kept as named constants
## so the next person to move the lane can grep for one number, not for a 104.
const TOAST_LANE_TOP := 126.0
const TOAST_LANE_H := 26.0
const TOAST_LANE_W := 720.0
## Breathing room left around a HUD element when the marker is pushed off it.
const AVOID_PAD := 14.0
## Group scans are cheap but not free; three times a second is invisible to the
## player and inaudible to the frame budget.
const RESOLVE_INTERVAL := 0.3
## World pixels per "metre". A region is ~1600px across, which reads as a
## believable 50m room rather than "1600 units, good luck".
const PX_PER_METRE := 32.0
## Inside this radius the target is right in front of you; the marker steps
## aside rather than parking itself on the NPC's face.
const NEAR_RADIUS := 130.0
## How high above the target the on-screen beacon floats, for a target that
## carries no art and no text of its own (a token, a prop). Portals and NPCs
## both do, and both measure their own clearance — see `_portal_clearance` and
## `_npc_clearance`.
const BEACON_LIFT := 52.0
## World-space nudge applied to the target before it is projected: the beacon
## aims a little above a thing's origin, which for a character is its feet. Used
## by the clearance functions too, so the two can never drift apart.
const SP_NUDGE := 14.0
## Visibility test padding — near the full frame, so anything the player can
## actually see gets a beacon rather than an edge arrow.
const VIEW_PAD_X := 44.0
const VIEW_PAD_TOP := 104.0
const VIEW_PAD_BOTTOM := 84.0

## Padding around the readout's own text box. There is no plate any more, so
## this is pure spacing between the chevron and the words.
const PLATE_PAD_X := 4.0
const PLATE_PAD_Y := 2.0
## THE MARKER'S OWN GEOMETRY, in UI units, at MAG_ON_SCREEN.
##
## The chevron is 19 units from origin to point and 12 the other way, and the
## dark seat behind it is the same shape at OUTLINE_GIRTH. So:
##   CHEVRON_REACH   how far the marker reaches TOWARD what it points at
##   CHEVRON_BACK    how far it reaches the other way, which is the side the
##                   readout hangs off when the beacon is aimed down at a target
## Both are quoted at magnification 1 and scaled by the live magnification.
const CHEVRON_REACH := 24.7
const CHEVRON_BACK := 15.6
const RING_REACH := 24.7
## The dark seat, one step larger than the body — LAW 7's "1px outline in
## #0A0C16", applied to the one piece of UI that lives out in the world.
const OUTLINE_GIRTH := 1.3
## How big the marker is drawn in each of its two states. Whole-ish numbers on
## purpose: the polygon is REBUILT at this magnification and rounded to whole
## units, never scaled by a Node2D transform (see `_aim`).
const MAG_ON_SCREEN := 1.0
const MAG_PINNED := 1.2
## Clear air between the chevron's outer edge and the nearest edge of the
## readout. Never below 8: closer than that and the words read as part of the
## marker rather than as a caption under it.
const PLATE_GAP := 12.0
## The band at the top of the screen that guidance owns and may not leave.
## Below it: the strip's cycle line ends at ~96. Above it: boss_hud.gd starts its
## announcement band at 222 precisely because this node hangs a readout here. A
## readout partly in this band and partly below it is what printed a line across
## a boss entrance card, so it is either wholly inside or wholly below.
const GUIDE_BAND_TOP := 112.0
const GUIDE_BAND_BOTTOM := 190.0
## CLEAR AIR the on-screen beacon keeps above whatever it is pointing at.
##
## Round 6 floated it a flat BEACON_LIFT of 52 screen px over the target's
## ORIGIN, and an origin is not an outline: a portal's mouth reaches 48 WORLD
## units in every direction, which at the camera's zoom is more than the lift —
## so region_production.png and region_corporate_enterprise.png show the chevron
## sitting on the swirl, on top of the portal's own "→ GPU Mines" label.
## Guidance may not cover the thing it is pointing at, and it may never cover a
## label; both numbers are measured from the target's real TOP EDGE now.
##
## ROUND 11: for a PORTAL this is now the gap between the swirl's top edge and
## the chevron's own downward TIP, not its centre. A clearance measured to a
## centre is a promise about a point in the middle of a 40-unit-tall shape; a
## clearance measured to the tip is the actual distance a viewer sees, and it is
## the only version of the number that can be checked against a frame.
const PORTAL_BEACON_CLEAR := 40.0
const NPC_LABEL_CLEAR := 44.0
## Fallbacks for the two measurements, used only when the live node cannot be
## read: region_portal.gd's BODY_RADIUS, and npc.gd's nameplate top
## (NAME_BOTTOM_Y -86 less a line of 14px type).
const PORTAL_BODY_RADIUS := 48.0
const NPC_NAME_TOP := -110.0
## Screen margin the readout is hard-clamped inside as a last resort.
const PLATE_EDGE_PAD := 12.0

const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## The chevron, pointing "up" (-Y), in whole units. Every orientation the marker
## can take is this shape rotated by a whole eighth of a turn and rounded back
## onto the grid — see `_aim`. It is never rotated as a transform.
## NOTE: this is a typed Array, not a PackedVector2Array. `PackedVector2Array([...])`
## is a runtime conversion, not a constant expression, and `const` rejects it
## ("Assigned value for constant isn't a constant expression") — which killed the
## whole script, and with it hud.gd, silently. An Array[Vector2] literal of
## Vector2 constructors IS constant-foldable; `_add_chevron` packs it.
const CHEVRON_PTS: Array[Vector2] = [
	Vector2(0, -19), Vector2(14, 12), Vector2(0, 4), Vector2(-14, 12),
]
## An eighth of a turn: the only angular step the marker is allowed.
const OCTANT := PI * 0.25

## Dry consolation prize for when the quest system has nothing for you.
const IDLE_TARGET_NAME := "Way out"

var _marker: Node2D
var _outline: Polygon2D
var _body: Polygon2D
## Kept as a positioning box only: it carries a StyleBoxEmpty, so the geometry
## below (which measures the readout as a rect) still works and nothing is drawn.
var _plate: Panel
var _label: Label

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
## True when the target is an NPC. They carry a nameplate above their head, and
## it is the one piece of world text the beacon is most likely to land on.
var _target_is_npc := false
## The region's ACCENT (LAW 2). The HUD pushes it in on every region change; the
## mode of the chevron is carried by its WORDS now, not by a second hue.
var _accent := _GameTheme.CYAN

## Which of the eight directions the chevron is currently built for, and at which
## magnification. -1 is "nothing built yet". The polygons are only rewritten when
## one of the two actually changes — for a beacon sitting over a target that is
## once, ever.
var _octant := -1
var _mag := 0.0

var _t := 0.0
var _resolve_t := 999.0
var _metres := 0
var _compass := ""
var _player_cache: Node2D = null
var _last_label_name := ""
var _last_label_metres := -1
var _last_label_cross := false

## HUD elements the marker must never sit on top of. Recomputed only when the
## viewport size changes, so the per-frame cost is two Rect2 point tests.
var _view_size := Vector2.ZERO
var _ex_quest := Rect2()
var _ex_toast := Rect2()

func _ready() -> void:
	name = "ObjectiveWaypoint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A MARKER THAT STOPS TICKING MUST STILL BE ABLE TO HIDE ITSELF. Everything
	# that takes the screen from the player also pauses the tree — a scripted
	# event, a dialogue, the pause menu — and a pausable `_process` cannot run
	# `_should_hide()` to get out of the way. It freezes instead, visible, at
	# whatever it was pointing at before, which is how region_production.png
	# ended up showing GPU Mines' chevron inside Production's portal. The work
	# this does while paused is one group scan every RESOLVE_INTERVAL and an early
	# return out of `_should_hide()`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	QuestManager.quest_started.connect(_on_quest_signal)
	QuestManager.quest_updated.connect(_on_quest_signal)
	QuestManager.quest_completed.connect(_on_quest_signal)
	GameManager.region_changed.connect(_on_region_change)
	# The objective line is content-sized, so re-measure the exclusion whenever
	# it changes instead of only on a viewport resize (which in a windowed
	# session may never happen after startup).
	var qp := get_parent().get_node_or_null("QuestPanel") if get_parent() else null
	if qp is Control:
		(qp as Control).item_rect_changed.connect(func() -> void:
			_refresh_exclusions(size)
		)
	set_process(true)

## Two polygons. That is the whole marker.
func _build() -> void:
	_marker = Node2D.new()
	_marker.name = "Marker"
	_marker.visible = false
	# NEVER ROTATED, NEVER SCALED. `_aim` rewrites the polygons instead, so every
	# vertex the marker ever has is a whole number of UI units (LAW 1). A rotated
	# transform is what made the token_vault arrow a smooth triangle.
	_marker.rotation = 0.0
	_marker.scale = Vector2.ONE
	add_child(_marker)

	# The dark seat is drawn first (behind), the accent body over it. Both carry
	# the same points at different magnifications — see `_aim`.
	_outline = _add_chevron(CHEVRON_PTS,
		Color(_GameTheme.VOID.r, _GameTheme.VOID.g, _GameTheme.VOID.b, 0.9), OUTLINE_GIRTH)
	_body = _add_chevron(CHEVRON_PTS, _accent, 1.0)
	_aim(Vector2.DOWN, MAG_ON_SCREEN)

	# Positioning box for the readout. StyleBoxEmpty: the opaque bordered plate
	# with the accent lip and the shadow is gone, and the text stands on its own
	# one-pixel shadow like every other label in the game (LAW 4).
	_plate = Panel.new()
	_plate.name = "WaypointPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.visible = false
	_plate.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	add_child(_plate)

	_label = Label.new()
	_label.name = "WaypointReadout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.clip_text = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The readout is a HUD label that happens to live out in the world, so it is
	# dressed like every other one: the aliased font, the SMALL tier, TEXT_DIM,
	# a 1px shadow, no halo and no plate (LAW 4). It used to be printed in the
	# region ACCENT, which made "Localhost · 14m" as loud as the chevron it hangs
	# off — two elements shouting the same thing in the same colour. The CHEVRON
	# carries the accent; the words are quiet.
	_label.add_theme_font_override("font", _GameTheme.ui_font())
	_label.add_theme_font_size_override("font_size", _GameTheme.SMALL)
	_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_GameTheme.outline_text(_label)
	_plate.add_child(_label)

## One layer of the chevron. `sc` is the shape's GIRTH, baked into the points by
## `_aim` rather than applied as a transform: a Polygon2D scaled by 1.3 has
## fractional vertices, and fractional vertices are the soft edges LAW 1 forbids.
## It is stored on the node so `_aim` can rebuild both layers from one loop.
func _add_chevron(pts: Array[Vector2], col: Color, sc: float) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array(pts)
	p.color = col
	p.scale = Vector2.ONE
	p.antialiased = false
	p.set_meta("girth", sc)
	_marker.add_child(p)
	return p

## Point the marker along `dir`, SNAPPED to one of eight directions, by rebuilding
## the polygons rather than by rotating them.
##
## The base shape points up (-Y), and the old code aimed it with
## `rotation = dir.angle() + PI/2`; the same expression picks the octant here.
## Each vertex is scaled by the layer's girth and the magnification, rotated by a
## whole eighth of a turn, and ROUNDED — so a diagonal chevron is still built out
## of whole units and rasterises with the same hard edges as the cardinal ones.
##
## Rebuilds only when the octant or the magnification actually changes.
func _aim(dir: Vector2, mag: float) -> void:
	var oct := 4
	if dir.length_squared() > 0.000001:
		oct = posmod(int(round((dir.angle() + PI * 0.5) / OCTANT)), 8)
	if oct == _octant and is_equal_approx(mag, _mag):
		return
	_octant = oct
	_mag = mag
	var a := float(oct) * OCTANT
	for layer: Polygon2D in [_outline, _body]:
		if not is_instance_valid(layer):
			continue
		var girth: float = float(layer.get_meta("girth", 1.0)) * mag
		var pts := PackedVector2Array()
		for p: Vector2 in CHEVRON_PTS:
			pts.append((p * girth).rotated(a).round())
		layer.polygon = pts

# ------------------------------------------------------------------ signals --
## Any quest/region change invalidates the cached node. Resolving is deferred to
## the next frame on purpose: on region_changed the world has not rebuilt yet
## (the HUD's handler runs before the world's), so scanning now would find the
## corpses of the old region.
func _on_quest_signal(_a = null, _b = null) -> void:
	_resolve_t = RESOLVE_INTERVAL

## A REGION CHANGE INVALIDATES THE MARKER, not just its cache.
##
## The portal it is pointing at is about to be freed with the room, and the room
## that replaces it has not been built yet — so for one frame there is genuinely
## nothing to point at, and for longer than that if the new region opens with a
## scripted event (production, corporate_enterprise) that stops this node
## ticking. Dropping the target and hiding HERE, from the signal handler, is what
## makes those two cases show nothing instead of the last room's chevron sitting
## in the new room's portal.
func _on_region_change(_region_id: String = "") -> void:
	_target = null
	_had_target = false
	_target_is_portal = false
	_target_is_npc = false
	_show(false)
	_on_quest_signal()

## Public: force an immediate re-resolve (the HUD calls this on demand).
func refresh_now() -> void:
	_resolve()

## Public: the region's ACCENT, pushed in by the HUD on every region change, so
## the chevron and the objective line are always the same one colour (LAW 2).
func set_accent(c: Color) -> void:
	if c == _accent:
		return
	_accent = c
	_apply_accent()

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

## Distance/compass are kept current even while the marker is hidden, so the
## objective line is already correct the instant a modal closes.
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
	if _plate and _plate.visible != on:
		_plate.visible = on

## Panel-safe boxes, in screen space. Mirrors hud.gd's layout lanes; recomputed
## only when the window size actually changes. The radar box is gone with the
## radar (LAW 8), and the toast moved from the top-right rail to a single line
## above the ability bar.
func _refresh_exclusions(view: Vector2) -> void:
	_view_size = view
	# The objective line, bottom-left (hud.tscn QuestPanel). Measured off the
	# live node when it exists — it is content-sized.
	_ex_quest = Rect2(28.0, view.y - 96.0, 760.0, 56.0)
	var qp := get_parent().get_node_or_null("QuestPanel") if get_parent() else null
	if qp is Control and (qp as Control).visible:
		# Into THIS Control's space: it is a sibling on the same layer, but this
		# Control no longer starts at the layer's origin — it starts at the
		# world rect's corner.
		var r: Rect2 = (qp as Control).get_global_rect()
		r.position -= global_position
		if r.size.x > 1.0 and r.size.y > 1.0:
			_ex_quest = r
	# Toast line, bottom-centre. MUST track hud.gd's TOAST_BOTTOM / TOAST_W /
	# TOAST_H: the lane moved up to clear the ability slots by 36px, and a
	# readout parked on the lane's OLD row would now be sitting under the toast.
	_ex_toast = Rect2(view.x * 0.5 - TOAST_LANE_W * 0.5,
		view.y - TOAST_LANE_TOP, TOAST_LANE_W, TOAST_LANE_H)

## Slides a point out of a box along its shortest escape route.
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

## Two passes: escaping one box can drop you onto its neighbour.
func _avoid(p: Vector2) -> Vector2:
	for _i in 2:
		p = _push_out(p, _ex_quest)
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
	# THE FRAME IS THIS CONTROL, NOT THE WINDOW. Since the stage fit re-anchors
	# root Controls onto the world's letterbox (pixel_stage.gd), this full-rect
	# Control IS the world rect — 1280x720 — while the window it sits in may be
	# 3840 wide. Measuring the margins off the window put the pinned chevron and
	# every exclusion box 1280px out on the ultrawide.
	var view := size
	if view != _view_size:
		_refresh_exclusions(view)
	var sp: Vector2 = _world_to_ui(_target.global_position + Vector2(0, -SP_NUDGE), vp)
	var rect_pos := Vector2(MARGIN_X, MARGIN_TOP)
	var rect_size := Vector2(
		maxf(view.x - MARGIN_X * 2.0, 96.0),
		maxf(view.y - MARGIN_TOP - MARGIN_BOTTOM, 96.0)
	)
	# Two boxes on purpose: "is it visible" is judged against nearly the whole
	# frame, while the pinned arrow is clamped to the tighter panel-safe box. One
	# box for both would flip perfectly visible floor-level tokens into edge-arrow
	# mode just because they sit low on screen.
	var inside := Rect2(
		Vector2(VIEW_PAD_X, VIEW_PAD_TOP),
		Vector2(maxf(view.x - VIEW_PAD_X * 2.0, 64.0), maxf(view.y - VIEW_PAD_TOP - VIEW_PAD_BOTTOM, 64.0))
	).has_point(sp)
	# LAW 9: the waypoint pulses 0.9 -> 1.0. It pulses in OPACITY, applied at the
	# bottom of this function — a scale pulse puts the chevron's vertices on
	# fractional coordinates sixty times a second, which is the same soft-edge
	# fault as rotating it (LAW 1). Nothing else about the marker moves.
	var pulse := 0.9 + 0.1 * (0.5 + 0.5 * sin(_t * 3.0))
	# The marker's magnification, settled before anything is placed: every
	# clearance below is measured off the marker's real outer edge (see
	# CHEVRON_REACH), so the size has to be known first.
	var s := MAG_ON_SCREEN if inside else MAG_PINNED
	# Text — and therefore the readout's real box — before any geometry: every
	# offset below is computed from its measured size, which is what makes the
	# layout hold for "Open Source Wildlands" as well as for "Tokens".
	_update_label_text()
	# Which side of the chevron the readout hangs off. Straight up when the
	# beacon sits over its target; back toward the screen centre when pinned.
	var plate_dir := Vector2.UP
	# The readout hangs off the beacon's RESTING height, never its bobbing one:
	# text that breathes is harder to read, and an oscillating edge re-opens every
	# clearance argument twice a second instead of settling it once.
	var plate_anchor := Vector2.ZERO

	# How far the marker reaches on the side the readout hangs off. Aimed DOWN at
	# an on-screen target the readout sits above its back edge; pinned at the
	# screen edge it sits behind its tip.
	var back := CHEVRON_BACK * s
	if inside:
		# On screen: a beacon bobbing above the thing, aimed straight down at it,
		# and CLEAR of both the thing's own art and the thing's own label.
		var lift := BEACON_LIFT
		if _target_is_portal:
			lift = maxf(lift, _portal_clearance(vp, sp, s))
		elif _target_is_npc:
			lift = maxf(lift, _npc_clearance(vp))
		var bob := sin(_t * 2.6) * 4.0
		var pos := sp + Vector2(0, -lift + bob)
		# Keep the beacon out of the bands the HUD occupies (it is mounted behind
		# them). Clamped, it still sits directly above the target in X and still
		# points down at it, so the read is identical.
		pos.y = clampf(pos.y, MARGIN_TOP, view.y - MARGIN_BOTTOM)
		pos = _avoid_vertical(pos, _ex_quest)
		pos = _avoid_vertical(pos, _ex_toast)
		_marker.position = pos.round()
		_aim(Vector2.DOWN, s)
		plate_anchor = Vector2(pos.x, pos.y - bob)
	else:
		# Off screen: clamp to the margin box, aimed along the line to the target.
		var half := rect_size * 0.5
		var centre := rect_pos + half
		var d := sp - centre
		if absf(d.x) < 0.01 and absf(d.y) < 0.01:
			d = Vector2(0, -1)
		var k := minf(half.x / maxf(absf(d.x), 0.01), half.y / maxf(absf(d.y), 0.01))
		_marker.position = _avoid(centre + d * k).round()
		_aim(d, s)
		# Readout tucked back toward the screen centre so it never clips off-frame.
		plate_dir = -d.normalized()
		plate_anchor = _marker.position
		back = (RING_REACH if _cross_region else CHEVRON_REACH) * s

	_place_plate(plate_anchor, plate_dir, view, back + PLATE_GAP)

	var alpha := 1.0
	var p := _player()
	if is_instance_valid(p):
		var dist := p.global_position.distance_to(_target.global_position)
		if dist < NEAR_RADIUS:
			# You're on top of it. Back off — the prop's own [E] prompt takes over.
			alpha = lerpf(0.16, 1.0, clampf(dist / NEAR_RADIUS, 0.0, 1.0))
	if _fallback:
		alpha *= 0.6
	# LAW 9's 0.9 -> 1.0, on the chevron only: the words do not breathe.
	_marker.modulate.a = alpha * pulse
	_plate.modulate.a = alpha
	_show(true)

## The readout hangs off `anchor` along `dir`, offset by `clear` PLUS its own
## half-extent on that axis — half of a 400px-wide box is 200px, and a flat 46
## does not cover it, which is how a wide readout used to print through its own
## chevron.
##
## `anchor` is the marker's RESTING position, not its live one — see `_place`.
func _place_plate(anchor: Vector2, dir: Vector2, view: Vector2, clear: float) -> void:
	var s := _plate.size
	var along := absf(dir.x) * s.x * 0.5 + absf(dir.y) * s.y * 0.5
	var p := anchor + dir * (clear + along) - s * 0.5
	# Hugging the top of the safe box there is no room above the chevron. Move
	# the readout BESIDE it, toward the screen centre — never underneath it.
	# Under an on-screen beacon is exactly where the thing it points AT is
	# standing, and guidance may not hide its own target.
	if dir.y < 0.0 and p.y < GUIDE_BAND_TOP:
		var side := -1.0 if anchor.x > view.x * 0.5 else 1.0
		p = anchor + Vector2(side * (clear + s.x * 0.5), 0.0) - s * 0.5
	# Wholly inside the guidance band, or wholly below it. Straddling its lower
	# edge is what dropped a readout onto a boss entrance banner.
	if p.y < GUIDE_BAND_BOTTOM:
		p.y = clampf(p.y, GUIDE_BAND_TOP, maxf(GUIDE_BAND_BOTTOM - s.y, GUIDE_BAND_TOP))
	# Then off the HUD's own lines.
	var c := p + s * 0.5
	for _i in 2:
		c = _push_rect_out(c, s, _ex_quest)
		c = _push_rect_out(c, s, _ex_toast)
	p = c - s * 0.5
	p.x = clampf(p.x, PLATE_EDGE_PAD, maxf(view.x - s.x - PLATE_EDGE_PAD, PLATE_EDGE_PAD))
	# The floor is MARGIN_BOTTOM, not the screen edge: below it live the ability
	# slots and the key legend, and a last-resort clamp must not be the one thing
	# that drops a readout onto the player's own hotkeys.
	p.y = clampf(p.y, GUIDE_BAND_TOP, maxf(view.y - MARGIN_BOTTOM - s.y, GUIDE_BAND_TOP))
	# Whole pixels: a half-pixel origin softens aliased text (LAW 1).
	_plate.position = p.round()

## Rect-vs-rect version of `_push_out`: the readout is a box, not a point, so it
## has to escape by its own half-extent or it leaves a corner behind.
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

## WORLD -> UI. This chevron is a HUD element pointing at a world object, and
## since round 11 the two live in different viewports: the world renders inside
## the 640x360 pixel stage (pixel_stage.gd) while this Control lays out in window
## pixels, re-anchored by the stage fit so its own rect IS the letterbox.
## `PixelStage.world_to_ui` is the single conversion that joins them — the old
## `vp.get_canvas_transform()` now reads the MAIN viewport, which has no camera
## and would pin the chevron to the world's raw coordinates.
##
## The fallback is the pre-stage path, so a test rig that mounts this Control
## without a world still behaves.
## The result is in THIS Control's own space — `world_to_ui` answers in window
## pixels, and this Control's origin is the world rect's corner, not the window's.
func _world_to_ui(world_pos: Vector2, vp: Viewport) -> Vector2:
	var st := PixelStage.find(get_tree())
	if st != null:
		return st.world_to_ui(world_pos) - global_position
	return vp.get_canvas_transform() * world_pos

## Camera zoom, as the factor that turns world units into UI pixels. Every
## clearance below is quoted in SCREEN pixels but measured off WORLD geometry, so
## it has to pass through here or the beacon drifts every time the framing moves.
## Inside the stage the chain is zoom (0.5) x stage-to-UI, which is what
## `world_to_ui_scale()` returns.
func _zoom_of(vp: Viewport) -> float:
	var st := PixelStage.find(get_tree())
	if st != null:
		var f := st.world_to_ui_scale()
		return f if f > 0.01 else 1.0
	var zoom: float = absf(vp.get_canvas_transform().get_scale().y)
	return zoom if zoom > 0.01 else 1.0

## The portal's body radius in WORLD units, read off its own artwork so the two
## files cannot disagree. region_portal.gd draws a 64px square at scale 1.5;
## PORTAL_BODY_RADIUS is only the fallback for a portal whose disc has not been
## built (no shader on disk, or a probe running before `_ready`).
func _portal_radius() -> float:
	var disc := _target.get_node_or_null("PortalDisc")
	if disc is Sprite2D:
		var s2 := disc as Sprite2D
		if s2.texture != null:
			return s2.texture.get_size().y * 0.5 * absf(s2.scale.y)
	return PORTAL_BODY_RADIUS

## How far above a PORTAL's projected position the beacon floats, as a lift from
## `sp`: enough that the chevron's downward TIP lands PORTAL_BEACON_CLEAR above
## the swirl's top edge. Attached to the doorway, never on it.
##
## The top edge is PROJECTED, not computed: the world point at the top of the
## disc goes through `_world_to_ui`, the same transform that placed `sp`. Round 7
## multiplied the radius by `_zoom_of()` instead and reached the same answer by a
## second route — two ways of asking where the portal is, which is one more than
## a guarantee can survive. One transform, one answer, and the clearance is then
## a plain subtraction in the space the marker is actually positioned in.
##
## The portal's own destination label lives BELOW the mouth (region_portal.gd
## LABEL_TOP), so clearing the art clears the text by construction — the beacon
## and the label are on opposite sides of the doorway and cannot meet.
func _portal_clearance(vp: Viewport, sp: Vector2, mag: float) -> float:
	var top: float = _world_to_ui(
		_target.global_position + Vector2(0, -_portal_radius()), vp).y
	return sp.y - (top - PORTAL_BEACON_CLEAR - CHEVRON_REACH * mag)

## How far above an NPC the beacon floats: NPC_LABEL_CLEAR above the TOP of
## their nameplate.
##
## Measured off the live Label because npc.gd MOVES it — the whole attention
## stack (name, quest marker, bark) lifts while that NPC is the tracked
## objective. Reading the node keeps the two in agreement without either file
## having to know the other's arithmetic.
##
## SIGN MATTERS. An earlier draft took `absf()` of the label's local y, which
## reads a label BELOW the target as if it were above it. A nameplate at or below
## the origin needs no clearance at all; only one genuinely overhead buys lift.
func _npc_clearance(vp: Viewport) -> float:
	var top := NPC_NAME_TOP
	var lab := _target.get_node_or_null("Label")
	if lab is Control:
		var r: Rect2 = (lab as Control).get_rect()
		if r.size.y > 1.0:
			top = r.position.y
	if top > -1.0:
		return BEACON_LIFT
	return (-top - SP_NUDGE) * _zoom_of(vp) + NPC_LABEL_CLEAR

## Repaints the CHEVRON in the current accent. Called on resolve and on a region
## change, never per frame.
##
## The readout is deliberately not repainted: it is TEXT_DIM in every room (see
## `_build`), so one element carries the region's colour instead of two.
func _apply_accent() -> void:
	if is_instance_valid(_body):
		_body.color = _accent

## ONE line, always: where you are headed and how far. Nothing else.
##
## ROUND 11 removes the last variant of it. Off screen the line used to read
## "Localhost · 14m · head for the portal", and region_token_vault.png is what
## that costs: an arrow, "Localhost · 14m · head for the portal" beside it, and
## the portal's own "← Return to Localhost" a few pixels above — THREE navigation
## cues stacked in one corner, all saying the same sentence. The instruction was
## also the least useful third of it, because the chevron is already pointing at
## the door and the door is already captioned. One line, one arrow, and the
## portal keeps its own name (LAW 4: wayfinding first, and once).
func _update_label_text() -> void:
	if _target_name == _last_label_name and _metres == _last_label_metres \
			and _cross_region == _last_label_cross:
		return
	_last_label_name = _target_name
	_last_label_metres = _metres
	_last_label_cross = _cross_region
	if _cross_region:
		_label.text = "%s · %dm" % [_target_name, _metres]
	elif _target_name == "":
		_label.text = "%dm" % _metres
	elif _metres <= 3:
		_label.text = _target_name
	else:
		_label.text = "%s · %dm" % [_target_name, _metres]
	_measure_plate()

## Shrink-to-fit: Controls grow to their minimum size but never shrink back on
## their own, and a stale width would drag the readout off-centre and re-open the
## "text sits on its own chevron" bug.
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
	# Same probe, same reason: `npc_id` is exactly what `_find_npc()` identifies
	# an NPC by, so the two can never disagree about what one is.
	_target_is_npc = is_instance_valid(_target) and not _target_is_portal \
		and "npc_id" in _target
	if previous != _target_name or prev_cross != _cross_region:
		_last_label_metres = -1
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

## World position of whatever we are pointing at.
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

## "28m NE" for the objective line, or "" when there's nothing to say.
func readout() -> String:
	if not is_instance_valid(_target):
		return ""
	if _compass == "":
		return "%dm" % _metres
	return "%dm %s" % [_metres, _compass]
