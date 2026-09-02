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
## away from the world it annotates. `fit_layer()` maps a screen-space
## CanvasLayer onto `world_rect`, and `world_to_ui()` is the one conversion
## anything pointing at a world position (the objective chevron) may use.
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
## How far the two fit axes may disagree before `fit_layer()` stops stretching
## the UI to the world's corners and centres it uniformly instead. See there.
const ASPECT_TOLERANCE := 0.8

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

## A world position in UI units — the coordinate space every screen-space
## CanvasLayer lays out in, AFTER `fit_layer()` has mapped that space onto
## `world_rect`. It is the inverse of the fit, so it stays correct whichever
## branch of `fit_layer()` is in force: a fitted layer draws UI point u at
## `fit_offset + fit_scale * u`, and stage pixel q lands at
## `world_rect.position + q * K`.
func world_to_ui(world_pos: Vector2) -> Vector2:
	var q := world_to_stage(world_pos)
	var window_px := world_rect.position + q * float(stage_k)
	var s := fit_scale()
	return Vector2(
		(window_px.x - fit_offset().x) / maxf(s.x, 0.0001),
		(window_px.y - fit_offset().y) / maxf(s.y, 0.0001))

## How many UI units one WORLD unit spans — the number every clearance quoted in
## screen pixels but measured off world geometry has to pass through.
func world_to_ui_scale() -> float:
	return STAGE_ZOOM * float(stage_k) / maxf(fit_scale().y, 0.0001)

## How many STAGE pixels one UI unit spans. world_label.gd measures the HUD's
## reserved lanes (authored in UI units) against captions living in the stage.
func ui_to_stage_scale() -> Vector2:
	return fit_scale() / maxf(float(stage_k), 1.0)

## THE UI FIT, as one transform: UI point u draws at `origin + scale * u`. Both
## halves come from here so the mapping and its inverse (`world_to_ui`) can never
## disagree about which branch is in force.
func _fit() -> Transform2D:
	var vp := get_viewport()
	if vp == null:
		return Transform2D.IDENTITY
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return Transform2D.IDENTITY
	var s := Vector2(world_rect.size.x / vs.x, world_rect.size.y / vs.y)
	var at := world_rect.position
	if minf(s.x, s.y) / maxf(maxf(s.x, s.y), 0.0001) < ASPECT_TOLERANCE:
		var u := minf(s.x, s.y)
		s = Vector2(u, u)
		at += (world_rect.size - vs * u) * 0.5
	return Transform2D(Vector2(s.x, 0.0), Vector2(0.0, s.y), at.floor())

## The scale half of the UI fit. See `fit_layer()` for the two branches.
func fit_scale() -> Vector2:
	return _fit().get_scale()

## The offset half of the UI fit.
func fit_offset() -> Vector2:
	return _fit().origin

## Map a screen-space CanvasLayer onto the world's letterbox rect.
##
## A CanvasLayer's transform is `origin + scale * point`, and Controls parented
## to one anchor against the VIEWPORT rect — so scaling the layer by
## `world_rect.size / viewport` and shifting it by `world_rect.position` lands a
## full-rect child exactly on the world, a bottom-anchored child exactly on the
## world's bottom edge, and so on, without touching a single Control. That is the
## whole reason this is a transform and not a re-layout: hud.gd, dialogue_ui.gd
## and the modal panels are not ours to edit, and they do not have to be.
func fit_layer(layer: CanvasLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	# The two fit axes agree exactly when the window is 16:9, and closely enough
	# not to matter for anything near it (a 1920x928 window lands at 0.86, which
	# reads as slightly condensed type and nothing else). On a window shaped
	# nothing like the stage — the 3840x928 ultrawide, where the axes differ by
	# 2.3x — stretching the HUD to the corners turns the resource counter into a
	# smear, so past ASPECT_TOLERANCE the fit goes uniform and centres inside the
	# world rect instead: correct letterforms, still entirely inside the world, at
	# the cost of some air between the HUD and the world's own edges.
	layer.scale = fit_scale()
	layer.offset = fit_offset()

## Undo fit_layer(). Only the guide overlay needs this — it is an autoload's
## child and outlives the world scene, so it must not carry the world's letterbox
## into the main menu.
static func reset_layer(layer: CanvasLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.scale = Vector2.ONE
	layer.offset = Vector2.ZERO
