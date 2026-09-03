class_name PixelStage
extends SubViewportContainer
## THE PIXEL GRID, MADE REAL — VISUAL_BIBLE_V2 LAW 1.
##
## The defect this exists to fix: this machine's screen is 3840x1080, a 1080-tall
## window does not fit under the menu bar, and `window/stretch/aspect="keep_width"`
## made Godot shrink the whole window to keep the ratio — 1649x928. Under
## `window/stretch/mode="canvas_items"` against a 1920x1080 base that is a 0.859
## magnification of EVERYTHING — the player sprite included. World art is 32px
## drawn at scale 2.0 under a zoom-1.6 camera, so one art pixel landed on 2.75
## screen pixels: runs of 2 and 3 alternating down every edge in the frame, which
## is what "AI slop" looks like when the cause is the renderer rather than the
## art. LAW 1 asks for exactly K screen pixels per art pixel, K a whole number.
##
## (With the aspect hack gone the same window now opens 1920x928 — only the height
## is clamped to the work area — and K is 2 either way.)
##
## The fix is structural, not a setting:
##
##   * The WORLD renders into a fixed 640x360 SubViewport. The camera runs at
##     zoom 0.5, so 1280x720 WORLD units are visible; a region is 20x15 tiles of
##     64 = 1280x960, i.e. exactly one screen wide (no horizontal scroll, the
##     Zelda framing) and 1.33 screens tall. World art at scale 2.0 therefore
##     puts one art pixel on exactly ONE SubViewport pixel.
##   * This container draws that SubViewport at `scale = K` with NEAREST
##     filtering, where K = floor(min(window_w / 640, window_h / 360)) — 2 in the
##     1920x928 window, 3 on a full 1920x1080. The
##     result is centred and the rest of the window is left to the clear colour:
##     a letterbox is the honest answer to a window that is not 16:9.
##   * `project.godot` runs `window/stretch/mode="disabled"`, so the main
##     viewport IS the window and nothing multiplies this container by 0.859
##     again. UI lays out in window pixels.
##
## Because the world now lives inside its own letterbox, the UI has to as well —
## on the 3840-wide screen a HUD anchored to the WINDOW corners would sit 960px
## away from the world it annotates. `fit_layer()` re-anchors a screen-space
## CanvasLayer's root Controls onto `world_rect`, and `world_to_ui()` is the one
## conversion anything pointing at a world position (the objective chevron) may
## use.
##
## Everything here is derived from two numbers and recomputed on `size_changed`;
## there is no state to get out of sync.

## The stage, in SubViewport pixels. 16:9, and small enough that K >= 2 on any
## display this game will meet.
const WORLD_W := 640
const WORLD_H := 360
## Camera2D magnification inside the stage (scenes/player/player.tscn). At 0.5 a
## 640x360 stage sees 1280x720 world units, and a 2.0-scaled 32px sprite is 32
## stage pixels. Anything that changes this breaks LAW 1.
const STAGE_ZOOM := 0.5
const GROUP := "pixel_stage"

## THE OFFSET CORRECTION A FITTED CONTROL IS CARRYING, one float per Side, parked
## on the Control itself. See `fit_control()` for what it means; metadata rather
## than a table in this node so the record cannot outlive the node it describes,
## and so a Control that is freed, reparented or fitted by a different stage
## carries its own truth with it.
const FIT_META := "_stage_fit"
## Marks a CanvasLayer whose root Controls are fitted, so world.gd can tell
## whether a Control that just appeared belongs to the fit.
const LAYER_META := "_stage_fitted"

## Emitted after every relayout with the world's rect in WINDOW pixels. world.gd
## re-fits the UI layers off this.
signal stage_changed(rect: Rect2)

## Screen pixels per stage pixel. Always a whole number >= 1.
var stage_k := 1
## Where the world is, in window pixels. UI must stay inside it.
var world_rect := Rect2(Vector2.ZERO, Vector2(float(WORLD_W), float(WORLD_H)))

var _view: SubViewport

## The stage for the running scene, or null. Group lookup rather than a path so
## nothing outside world.tscn has to know where this node lives.
static func find(tree: SceneTree) -> PixelStage:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as PixelStage

func _ready() -> void:
	add_to_group(GROUP)
	# The container is a plain blitter: it must not eat clicks meant for the HUD,
	# and it must not resample. (Non-positional input — every key this game reads
	# — is forwarded into the SubViewport by the container regardless of
	# mouse_filter; verified, because player.gd's abilities live in
	# _unhandled_input.)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch = false
	# Position and size are computed, so the layout system must not also have an
	# opinion: anchors at the top-left make `position`/`size` the whole story.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_view = get_node_or_null("Viewport") as SubViewport
	_configure_view()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_relayout):
		vp.size_changed.connect(_relayout)
	_relayout()

## Everything the stage needs that a .tscn would express less legibly, set in one
## place so the grid cannot be half-configured.
func _configure_view() -> void:
	if _view == null:
		return
	_view.size = Vector2i(WORLD_W, WORLD_H)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Bloom stays INSIDE the stage: the glow pass reads an HDR buffer, and an
	# own World3D keeps world.gd's WorldEnvironment off the main viewport, where
	# it would put a second bloom on the already-bloomed blit and on the HUD.
	_view.use_hdr_2d = true
	_view.own_world_3d = true
	_view.disable_3d = true
	_view.transparent_bg = false
	# Whole-pixel canvas items are what keeps the grid intact while the camera
	# scrolls; camera_fx.gd quantises the camera itself to stage pixels on top.
	_view.snap_2d_transforms_to_pixel = true
	_view.snap_2d_vertices_to_pixel = true

func _relayout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	stage_k = maxi(1, int(floorf(minf(vs.x / float(WORLD_W), vs.y / float(WORLD_H)))))
	var px := Vector2(float(WORLD_W * stage_k), float(WORLD_H * stage_k))
	# floor(), not round(): a half-pixel origin is harmless (NEAREST sampling at
	# an exact integer SCALE still emits runs of exactly K), but a whole number
	# is free and easier to reason about in the capture proof.
	var at := ((vs - px) * 0.5).floor()
	size = Vector2(float(WORLD_W), float(WORLD_H))
	scale = Vector2(float(stage_k), float(stage_k))
	position = at
	world_rect = Rect2(at, px)
	stage_changed.emit(world_rect)

## The SubViewport the world renders into.
func view() -> SubViewport:
	return _view

## A world position in STAGE pixels (0..640, 0..360). This is the camera's own
## canvas transform, which is the only thing that knows where the frame is.
func world_to_stage(world_pos: Vector2) -> Vector2:
	if _view == null:
		return world_pos
	return _view.get_canvas_transform() * world_pos

## A world position in UI units. UI UNITS ARE WINDOW PIXELS: the fit below leaves
## every CanvasLayer's transform at identity and re-anchors its root Controls
## instead, so there is no second space to invert. Stage pixel q lands at
## `world_rect.position + q * K`, and that is the whole conversion.
func world_to_ui(world_pos: Vector2) -> Vector2:
	return world_rect.position + world_to_stage(world_pos) * float(stage_k)

## How many UI units one WORLD unit spans — the number every clearance quoted in
## screen pixels but measured off world geometry has to pass through. The camera
## halves world units into stage pixels and the blit multiplies them by K, so at
## K=2 one world unit is exactly one window pixel.
func world_to_ui_scale() -> float:
	return STAGE_ZOOM * float(stage_k)

## How many STAGE pixels one UI unit spans. world_label.gd measures the HUD's
## reserved lanes (authored in UI units) against captions living in the stage.
func ui_to_stage_scale() -> Vector2:
	var s := 1.0 / maxf(float(stage_k), 1.0)
	return Vector2(s, s)

# -------------------------------------------------------------- the UI fit ---
##
## THE ULTRAWIDE HUD BUG, AND WHY THIS IS A RE-LAYOUT AND NOT A TRANSFORM.
##
## The fit this replaces scaled the whole CanvasLayer by `world_rect.size /
## window`. It looked right because a Control parented to a CanvasLayer anchors
## against the WINDOW, so a full-rect child came out window-sized and the scale
## brought it back down onto the world. But those two halves disagree the moment
## the window stops being 16:9. On this machine's 3840x928 the layer scale fell
## back to a uniform 1280/3840 = 0.333 while the Controls were still laying
## themselves out across 3840 window pixels, so the HUD drew at HALF the size it
## has in a 1920 window — measured off `region_localhost_wide.png`: "75 tk · 20
## cp" at (1286, 326) instead of (348, 122), the waypoint readout with it. A UI
## whose size depends on how wide the window happens to be is not a UI anyone can
## design, and a fractional layer scale was also quietly resampling the aliased
## font LAW 1 exists to keep crisp.
##
## So: the layer transform is IDENTITY and UI units are window pixels. Each root
## Control keeps its authored anchors — anchors are how a HUD says "bottom-left",
## and rewriting them would break the Containers, grow flags and minimum sizes
## underneath — and carries a per-side OFFSET CORRECTION that turns "anchored to
## the window" into "anchored to the world rect":
##
##     the engine puts side s at   anchor * window_dim + offset
##     the world rect wants it at  anchor * world_dim  + offset + world_pos
##     correction = anchor * (world_dim - window_dim) + world_pos
##
## A full-rect Control therefore lands EXACTLY on `world_rect`, a centre-anchored
## modal exactly in its middle, and every glyph draws at the size it was authored
## at, on whole pixels, at every window size. The correction currently applied is
## remembered on the Control so a re-fit can undo the previous one; that is the
## only state, and it lives on the node it describes.

## No correction — the identity record, and what an unfitted Control implies.
## (A PackedFloat32Array literal is not a constant expression, so this is a
## function rather than a `const`.)
static func _no_fit() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

## The correction each side of `c` needs to anchor against the world rect.
func _corrections(c: Control) -> PackedFloat32Array:
	var out := _no_fit()
	var vp := get_viewport()
	if vp == null:
		return out
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return out
	var span := world_rect.size - vs
	out[SIDE_LEFT] = c.anchor_left * span.x + world_rect.position.x
	out[SIDE_TOP] = c.anchor_top * span.y + world_rect.position.y
	out[SIDE_RIGHT] = c.anchor_right * span.x + world_rect.position.x
	out[SIDE_BOTTOM] = c.anchor_bottom * span.y + world_rect.position.y
	return out

## Lay a screen-space CanvasLayer out inside the world's letterbox rect.
func fit_layer(layer: CanvasLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.scale = Vector2.ONE
	layer.offset = Vector2.ZERO
	layer.set_meta(LAYER_META, true)
	for c in layer.get_children():
		if c is Control:
			fit_control(c as Control)

## Fit ONE root Control of a fitted layer. Idempotent: it removes the correction
## the Control is already carrying before applying the one the current letterbox
## asks for, so it can be called on every resize and on every panel that arrives
## later — the pause menu, the death screen, the quest log — without stacking.
func fit_control(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	var want := _corrections(c)
	var have := _no_fit()
	if c.has_meta(FIT_META):
		have = c.get_meta(FIT_META)
	for s: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		c.set_offset(s, c.get_offset(s) - have[s] + want[s])
	c.set_meta(FIT_META, want)

## Write an AUTHORED offset — the number the .tscn would have carried — onto a
## Control that may or may not have been fitted yet, correction included.
##
## modal_panel.gd's `place_centred` is the caller that needs this: the map panel
## re-heights itself every time its zoom changes, long after the fit has been
## through it, and "set offset_top to -h/2" has to mean the same thing both
## times.
func author_offset(c: Control, side: int, value: float) -> void:
	if c == null or not is_instance_valid(c):
		return
	var want := _corrections(c)
	var have := _no_fit()
	if c.has_meta(FIT_META):
		have = c.get_meta(FIT_META)
	have[side] = want[side]
	c.set_offset(side, value + want[side])
	c.set_meta(FIT_META, have)

## Undo fit_layer(). Only the guide overlay needs this — it is an autoload's
## child and outlives the world scene, so it must not carry the world's letterbox
## into the main menu.
static func reset_layer(layer: CanvasLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.scale = Vector2.ONE
	layer.offset = Vector2.ZERO
	if layer.has_meta(LAYER_META):
		layer.remove_meta(LAYER_META)
	for c in layer.get_children():
		if c is Control:
			reset_control(c as Control)

## Give one Control its authored layout back.
static func reset_control(c: Control) -> void:
	if c == null or not is_instance_valid(c) or not c.has_meta(FIT_META):
		return
	var have: PackedFloat32Array = c.get_meta(FIT_META)
	for s: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		c.set_offset(s, c.get_offset(s) - have[s])
	c.remove_meta(FIT_META)
