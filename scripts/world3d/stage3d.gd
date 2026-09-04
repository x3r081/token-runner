extends Node
## WORLD -> SCREEN, for UI that points at things (3D_BIBLE.md §3).
##
## The 2D game joins its world and its HUD through exactly two numbers, and
## pixel_stage.gd's header names them: `world_to_ui()` (where on screen is this
## world position) and `world_to_ui_scale()` (how many screen pixels is one
## world unit). objective_waypoint.gd's chevron and every clearance it measures
## go through that pair; world_label.gd goes through `ui_to_stage_scale()`.
##
## This node answers the same three questions for the 3D world, in the same
## units, so a UI script needs one lookup swapped and no new concepts:
##
##   * MAP PIXELS in, always (3D_BIBLE §2 — the managers' lingua franca). The
##     conversion to world units happens inside, via Map3D.
##   * WINDOW PIXELS out. There is no pixel stage in 3D and no letterbox: the
##     3D world renders into the main viewport, so a Camera3D unprojection is
##     already in the space a CanvasLayer's Controls lay out in. That is why
##     `stage_k` is 1 and `world_rect` (the letterbox in 2D) is free to mean
##     the REGION rect instead.
##
## Found by group "stage3d". No `class_name` — `World3D` is a real Godot class
## and this whole family of names sits close to the engine's; consumers
## duck-type off the group, exactly as they duck-type `camera_fx`.
##
##   var st := get_tree().get_first_node_in_group("stage3d")
##   if st: at = st.world_to_ui(target_map_px)

const GROUP := "stage3d"

## The height, in world units, that a map position is lifted to before being
## projected: mid-body on a 0.9u character (3D_BIBLE §3). A chevron aimed at
## the floor under an NPC points at their feet and reads as pointing past them.
const PROBE_HEIGHT := 0.5
## The baseline the scale is measured over. One tile, so the measurement is
## taken across real geometry rather than across a rounding error.
const SCALE_BASE := 64.0

## The current region, in MAP PIXELS. `Rect2(Vector2.ZERO, size)` — regions are
## authored from the origin (region_builder.gd), so the position is always zero
## and the size is the `size` the builder returned. world3d.gd writes it.
var world_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 960.0))
## Screen pixels per stage pixel. Always 1 in 3D: there is no blit. Present so
## a tool written against pixel_stage.gd's surface reads the same field.
var stage_k := 1

var _cam: Camera3D
var _scale_cache := 1.0
var _scale_frame := -1

func _ready() -> void:
	add_to_group(GROUP)

## The region's extent in map px, straight from the builder's `size`.
func set_world_rect(size_px: Vector2) -> void:
	if size_px.x > 0.0 and size_px.y > 0.0:
		world_rect = Rect2(Vector2.ZERO, size_px)

## The live 3D camera. Re-resolved rather than cached hard, because the rig is
## rebuilt by nothing today but a cutscene camera would be the obvious next
## thing to add and this must not go stale silently.
func camera() -> Camera3D:
	if is_instance_valid(_cam) and _cam.is_inside_tree() and _cam.current:
		return _cam
	_cam = null
	if not is_inside_tree():
		return null
	var vp := get_viewport()
	if vp != null:
		_cam = vp.get_camera_3d()
	return _cam

## A MAP-PIXEL position as a WINDOW-PIXEL position. The one conversion the UI
## may use, and the 3D twin of PixelStage.world_to_ui().
##
## `unproject_position` is only meaningful in front of the camera; behind it the
## projection flips and a chevron would point at the mirror image of its target.
## With a -56 degree top-down rig nothing in a room can get behind the near
## plane, but a caller probing a position outside the region (a portal in the
## next room, a quest target off-map) can, so the result is mirrored back
## through the screen centre: still off-screen, still on the correct side, which
## is all an edge-clamped chevron needs.
func world_to_ui(px: Vector2) -> Vector2:
	var cam := camera()
	if cam == null:
		return px
	var at := Map3D.to3d(px, PROBE_HEIGHT)
	var sp := cam.unproject_position(at)
	if cam.is_position_behind(at):
		var centre := _screen_size() * 0.5
		return centre + (centre - sp)
	return sp

## Alias for the 2D name, so a capture/QA tool written against pixel_stage.gd
## resolves. UI units and stage pixels are the same space here (stage_k == 1).
func world_to_stage(px: Vector2) -> Vector2:
	return world_to_ui(px)

## How many WINDOW pixels one MAP PIXEL spans at the player's depth — the
## number every clearance quoted in screen pixels but measured off world
## geometry has to pass through (objective_waypoint.gd `_zoom_of`).
##
## Measured, not derived: a perspective camera has no single magnification, so
## the honest answer is the local one. Two points one tile apart on the map's X
## axis, both at the player's position and probe height, unprojected and
## divided. Cached for the frame because the callers ask several times per
## `_draw`.
func world_to_ui_scale() -> float:
	var frame := Engine.get_process_frames()
	if frame == _scale_frame:
		return _scale_cache
	_scale_frame = frame
	_scale_cache = _measure_scale()
	return _scale_cache

func _measure_scale() -> float:
	var cam := camera()
	if cam == null:
		return 1.0
	var origin := _probe_origin()
	var a := Map3D.to3d(origin, PROBE_HEIGHT)
	var b := Map3D.to3d(origin + Vector2(SCALE_BASE, 0.0), PROBE_HEIGHT)
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return 1.0
	var span := cam.unproject_position(a).distance_to(cam.unproject_position(b))
	# A degenerate span (a camera mid-rebuild, a zero-size viewport) must not
	# hand the UI a divide-by-zero disguised as a scale.
	return span / SCALE_BASE if span > 0.01 else 1.0

## Where to take the measurement: at the player if there is one, otherwise at
## the middle of the room. Both are inside the frustum by construction, which
## is what keeps the unprojection meaningful.
func _probe_origin() -> Vector2:
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player")
		if p is Node3D and (p as Node3D).is_inside_tree():
			return Map3D.to_map((p as Node3D).global_position)
	return world_rect.size * 0.5

## How many STAGE pixels one UI unit spans. One-to-one in 3D; kept so
## world_label.gd's contract has an answer if it is ever pointed here.
func ui_to_stage_scale() -> Vector2:
	return Vector2.ONE

func _screen_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(1920.0, 1080.0)
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0)
