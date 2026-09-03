extends Control
## The one modal rule, in one place (VISUAL_BIBLE_V2 LAW 8).
##
## Round 6 is a SUBTRACTION round. Every screen used to bring its own panel: its
## own accent border, its own outer glow, its own sheen quad, its own row
## cascade, its own three font sizes. Ten screens, ten looks, and the frame read
## as generated rather than designed.
##
## Now there is exactly one modal look and it lives here:
##
##   * body BASE, OPAQUE, 1px LINE border, corner radius 2;
##   * no glow, no drop shadow, no sheen, no gradient, no per-screen accent
##     border — the panel is furniture, the content is the design;
##   * one ACCENT per screen (the title and the primary action), everything else
##     TEXT / TEXT_DIM;
##   * three type sizes, ever: SMALL / BODY / HEADING;
##   * the WORLD dims to 35% while one is open (`dim_world`), so the room
##     recedes instead of competing — and only the room: the HP bar, the cycle
##     clock and the objective line stay at full strength, because none of these
##     screens pauses the game;
##   * rows appear. They do not cascade, fade, breathe or stagger.
##
## Screens call modal_box() and use the size constants. That is the whole
## contract, and it is why they now look like one product.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

## The only three type sizes in the UI (LAW 1). Set the SIZE, never the font —
## every label inherits the theme's aliased default font, which is what keeps
## text crisp on pixel art. A per-label FontVariation reaches past the theme and
## lands back on the smooth fallback face; that is how the old headings ended up
## anti-aliased over a 2x pixel grid.
## ROUND 9: SMALL is 16, not 14, and MUST stay equal to GameTheme.SMALL — the
## nine screens that size their small tier off this constant were still printing
## at the size that rasterised "compiled" as "complled". The value lives in two
## places only because modal_panel.gd is deliberately free of a GameTheme
## dependency; if one ever moves, move the other.
const SMALL := 16
const BODY := 18
const HEADING := 26

## The HUD owns the bottom band (hud.gd: AbilityBar y -100..-42, HintBar
## y -34..-12, both bottom-anchored). A modal control drawn into it sits on top
## of an ability slot — the Dream App's "Close Console" used to land on slot 3,
## so the frame showed "Close Console" and "Rubber Duck" printed over each other
## and the player could not tell what they were about to press. (The bar itself
## is MOUSE_FILTER_IGNORE, so the click landed correctly; the frame lied.)
const HUD_BOTTOM_RESERVE := 108.0

## The band the HUD owns at the top: TopBar y 14..86 (hud.tscn) and the
## StatusStrip y 90..122 under it (hud.gd:_build_status_strip). Same rule as the
## bottom reserve, for the same reason — these modals do not pause the game, so
## the resource readout, the HP/focus bars and above all the cycle countdown
## ("the deadline the whole game hangs on", per hud.gd) have to stay visible
## while one is open. 128 clears both with 6px to spare.
const TOP_PAD := 128.0

## Never collapse a modal below this, whatever the viewport is.
const MIN_HEIGHT := 220.0

## Modal bodies are OPAQUE. "Near-opaque" was 0.96, and 4% of a lit world is a
## second layer of text: ui_quest_log.png prints "You walked past the desk
## again…" through the panel and across its own body copy, and ui_dream_app.png
## carries a prop silhouette behind the price list. The world recedes because the
## stage is DIMMED (see `dim_world`), not because the panel is thin.
const BODY_ALPHA := 1.0
const SCRIM_ALPHA := 0.86
const SCRIM_TINT := Color(0.012, 0.016, 0.038, 1.0)

## THE WORLD DIM, and the group it is applied to.
##
## pixel_stage.gd renders the entire world into one SubViewport and blits it as
## one CanvasItem, which makes "dim the world and nothing else" a single
## `modulate` on a single node — structurally incapable of touching the HUD, the
## panel, or anything else on a CanvasLayer. That is strictly better than the
## full-screen scrim it replaces, which had to be hand-placed at index 0 of the
## HUD layer to avoid dimming the HP bar and the cycle clock along with the room.
##
## 0.35: the room is still legible (you can see the boss walking toward you while
## you shop) and no longer competes with the panel's text.
const STAGE_GROUP := "pixel_stage"
const WORLD_DIM := 0.35
## Where a stage's own modulate is parked while it is dimmed, so restoring cannot
## invent a value that was never there.
const DIM_META := "_modal_dim_from"
## Marks a panel that is already holding the world down, so a screen that calls
## both `register_modal` and `attach_scrim` takes exactly one hold.
const HOLD_META := "_modal_dim_held"

## How many modals are currently holding the world down. Static: the panels are
## unrelated nodes and several can legitimately be open at once (the map over the
## pause menu). It outlives a scene reload, which is why hud.gd clears it when a
## fresh world comes up.
static var _dim_depth := 0

func register_modal() -> void:
	UIManager.push_modal()
	# Idempotent per panel, so a screen that also calls `attach_scrim` does not
	# hold the world down twice.
	dim_world(self)
	tree_exiting.connect(_unregister_modal, CONNECT_ONE_SHOT)

func _unregister_modal() -> void:
	UIManager.pop_modal()

# ----------------------------------------------------------- world dim ----

## Dim the world for as long as `panel` is on screen.
##
## Idempotent per panel (a screen may call this and `attach_scrim`, and both go
## through here), and the release is bound to the panel's own `tree_exiting`, so
## there is no close path that can forget it — including `queue_free()` from
## world.gd's toggle, a region change taking the panel with it, or the whole HUD
## going away.
static func dim_world(panel: Control) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	if panel.has_meta(HOLD_META):
		return
	panel.set_meta(HOLD_META, true)
	var tree := panel.get_tree()
	_dim_depth += 1
	_apply_world_dim(tree, true)
	# The tree is captured rather than read back on the way out: by the time
	# `tree_exiting` fires the panel is on its way off the tree and may no longer
	# be able to answer `get_tree()`.
	var release := func() -> void:
		_release_world_dim(tree)
	panel.tree_exiting.connect(release, CONNECT_ONE_SHOT)

## One panel let go. The world comes back when the last of them has.
static func _release_world_dim(tree: SceneTree) -> void:
	_dim_depth = maxi(0, _dim_depth - 1)
	if _dim_depth == 0:
		_apply_world_dim(tree, false)

## Drop every hold and put the world back. A fresh world calls this (hud.gd):
## `_dim_depth` is static and a panel that died with the previous scene never got
## to release it, which would open the new run at 35%.
static func clear_world_dim(tree: SceneTree) -> void:
	_dim_depth = 0
	_apply_world_dim(tree, false)

static func _apply_world_dim(tree: SceneTree, on: bool) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(STAGE_GROUP):
		var ci := n as CanvasItem
		if ci == null:
			continue
		if on:
			if not ci.has_meta(DIM_META):
				ci.set_meta(DIM_META, ci.modulate)
			var was: Color = ci.get_meta(DIM_META)
			ci.modulate = Color(WORLD_DIM * was.r, WORLD_DIM * was.g,
				WORLD_DIM * was.b, was.a)
		elif ci.has_meta(DIM_META):
			var back: Color = ci.get_meta(DIM_META)
			ci.modulate = back
			ci.remove_meta(DIM_META)

# ------------------------------------------------------------ shared kit ----

## THE panel. Flat BASE body, one hairline LINE border, radius 2, nothing else.
##
## `_accent` is kept in the signature (every screen passes one) but deliberately
## unused: a panel that borrows its border colour from the screen's accent is how
## eight differently-coloured frames happened. The accent belongs on the title
## and the primary button, where it means something.
static func modal_box(_accent: Color, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, BODY_ALPHA)
	s.border_color = _GameTheme.LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(margin)
	return s

## A 1px horizontal rule in LINE — the only divider the UI owns. Replaces the
## accent bar-gradient "rules" that used to sit above every choice block.
static func rule() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _GameTheme.LINE
	s.set_corner_radius_all(0)
	return s

## Make the world recede behind a modal.
##
## ROUND 11 MOVES THE DIM OFF THIS NODE. The scrim was a full-screen ColorRect
## pushed to index 0 of the HUD layer, and every line of that sentence was a
## compromise: index 0 so it would not also dim the HP bar and the cycle clock
## (modals do not pause the tree — the player is still being hit while the map is
## open), a sibling rather than a child so the panel's entrance tween could not
## fade it, a full-rect Control so it covered the same area the world does.
## `dim_world` gets all of that for free by modulating the pixel stage itself:
## the world is one CanvasItem, so dimming it cannot reach anything else, and
## there is no node to order, reparent or fade.
##
## The ColorRect survives, transparent, because it is still the honest owner of
## nothing at all: the name, the lifetime and the return value are unchanged for
## the three screens that call this, and `alpha` is still read so the signature
## does not lie about taking a number it no longer paints with.
static func attach_scrim(panel: Control, alpha: float = SCRIM_ALPHA) -> ColorRect:
	if panel == null or not panel.is_inside_tree():
		return null
	var parent := panel.get_parent()
	if parent == null:
		return null
	dim_world(panel)
	var scrim := ColorRect.new()
	scrim.name = "%sScrim" % panel.name
	scrim.color = _GameTheme.with_alpha(SCRIM_TINT, alpha * 0.0)
	# It draws nothing and it must never eat a click aimed at a HUD control; the
	# modal body itself is opaque and stops anything aimed at the panel.
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(scrim)
	parent.move_child(scrim, 0)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kill := func() -> void:
		if is_instance_valid(scrim):
			scrim.queue_free()
	panel.tree_exiting.connect(kill, CONNECT_ONE_SHOT)
	return scrim

## Panels re-placed when their content settles; see `place_centred`.
const PLACE_META := "_modal_place"
const HOOK_META := "_modal_place_hooked"

## THE FRAME A MODAL LIVES IN, which is the world's letterbox and not the window.
##
## On a 3840x928 ultrawide the window is 2560px wider than the game; a panel
## measured against it is centred on a desktop, not on a room. The pixel stage
## knows where the world is, so ask it, and fall back to the viewport for a rig
## that mounts a panel with no world around it (the main menu, a test).
static func stage_rect(panel: Control) -> Rect2:
	if panel == null or not panel.is_inside_tree():
		return Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0))
	var st := PixelStage.find(panel.get_tree())
	if st != null:
		return st.world_rect
	return panel.get_viewport_rect()

## The stage, but only for a panel the stage's letterbox correction applies to.
##
## That correction turns "anchored to the window" into "anchored to the world
## rect", so it belongs to a ROOT Control of a CanvasLayer and to nothing else: a
## panel nested inside another Control (the Dream App's body inside its full-rect
## root) is already measured against a parent the fit has put on the world, and
## correcting it a second time would push it down by the letterbox bar.
static func _root_stage(panel: Control) -> PixelStage:
	if panel == null or not panel.is_inside_tree():
		return null
	if not (panel.get_parent() is CanvasLayer):
		return null
	return PixelStage.find(panel.get_tree())

## The height a centre-anchored modal is allowed to be in that frame.
static func fitted_height(panel: Control, want_h: float,
		top_pad: float = TOP_PAD, bottom_reserve: float = HUD_BOTTOM_RESERVE) -> float:
	var vh: float = stage_rect(panel).size.y
	return minf(want_h, maxf(MIN_HEIGHT, vh - top_pad - bottom_reserve))

## Size a centre-anchored modal and centre it in the space the HUD is NOT using —
## below the top bar, above the ability bar. Nothing the player can click ends up
## on top of an ability slot, and nothing the player needs to read (tokens, HP,
## the cycle clock) ends up under the panel.
static func place_centred(panel: Control, want_h: float,
		top_pad: float = TOP_PAD, bottom_reserve: float = HUD_BOTTOM_RESERVE) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	panel.set_meta(PLACE_META, PackedFloat32Array([want_h, top_pad, bottom_reserve]))
	# EVERY SCREEN SETS ITS BOX BEFORE IT FILLS IT, so the minimum size that
	# decides how tall this panel really ends up is not known on this call. The
	# signal that says it changed is the only honest moment to place it again, and
	# the work is two offsets.
	if not panel.has_meta(HOOK_META):
		panel.set_meta(HOOK_META, true)
		panel.minimum_size_changed.connect(_replace_bound.bind(panel))
	_apply_place(panel)

## `place_centred` again, with the arguments it was last given.
static func _replace_bound(panel: Control) -> void:
	if is_instance_valid(panel) and panel.is_inside_tree():
		_apply_place(panel)

static func _apply_place(panel: Control) -> void:
	var args: PackedFloat32Array = panel.get_meta(PLACE_META)
	if args.size() < 3:
		return
	var frame := stage_rect(panel)
	var h := fitted_height(panel, args[0], args[1], args[2])
	# THE PANEL MAY BE TALLER THAN WE ASKED FOR, and used to hang out of the world
	# and onto the letterbox bar when it was: `h` is a request, a panel whose
	# content needs more grows past it downward, and the quest log (625 tall in a
	# 484 band) and the map both crossed the bottom edge of the room. Measure what
	# the box will ACTUALLY be and keep that inside the frame. A modal that cannot
	# fit the band may cover a HUD lane it was asked to clear; it may not leave the
	# room, because outside the room there is no game, only letterbox.
	var real_h := maxf(h, panel.get_combined_minimum_size().y)
	var room := maxf((frame.size.y - real_h) * 0.5, 0.0)
	var shift: float = clampf((args[1] - args[2]) * 0.5, -room, room)
	# These are AUTHORED offsets against centre anchors. A panel that re-heights
	# itself while it is open (the map, on every zoom step) has already been
	# through the stage fit by then, so the write goes through the stage when
	# there is one: it re-applies that panel's own letterbox correction instead
	# of dropping it on the floor.
	# Placing a panel can change its layout, which can change its minimum size,
	# which calls this again: settle for the answer we already have rather than
	# ringing.
	if args.size() >= 5 and is_equal_approx(args[3], real_h) and is_equal_approx(args[4], shift):
		return
	panel.set_meta(PLACE_META, PackedFloat32Array([args[0], args[1], args[2], real_h, shift]))
	var st := _root_stage(panel)
	if st != null:
		st.author_offset(panel, SIDE_TOP, -real_h * 0.5 + shift)
		st.author_offset(panel, SIDE_BOTTOM, real_h * 0.5 + shift)
		return
	panel.offset_top = -real_h * 0.5 + shift
	panel.offset_bottom = real_h * 0.5 + shift

## Rows appear. That is the whole animation.
##
## This used to be a bounded cascade, which was itself a fix for an unbounded
## cascade, which was a fix for rows that never reached full alpha. Three rounds
## of repairing an effect nobody asked for. A list that is simply THERE when the
## panel opens has none of those failure modes and reads as a shipped menu
## instead of a loading screen. Signature kept — every modal still calls it.
static func reveal_rows(container: Node, _window: float = 0.20) -> void:
	if container == null:
		return
	for c in container.get_children():
		if c is Control:
			(c as Control).modulate.a = 1.0
