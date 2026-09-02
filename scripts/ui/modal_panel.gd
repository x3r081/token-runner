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
##   * body BASE at 96%, 1px LINE border, corner radius 2;
##   * no glow, no drop shadow, no sheen, no gradient, no per-screen accent
##     border — the panel is furniture, the content is the design;
##   * one ACCENT per screen (the title and the primary action), everything else
##     TEXT / TEXT_DIM;
##   * three type sizes, ever: SMALL / BODY / HEADING;
##   * a scrim behind, so the world recedes instead of competing;
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
const SMALL := 14
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

## Modal bodies are near-opaque on purpose: a neon world caption reads straight
## through anything lighter and collides with the text on top of it.
const BODY_ALPHA := 0.96
const SCRIM_ALPHA := 0.86
const SCRIM_TINT := Color(0.012, 0.016, 0.038, 1.0)

func register_modal() -> void:
	UIManager.push_modal()
	tree_exiting.connect(_unregister_modal, CONNECT_ONE_SHOT)

func _unregister_modal() -> void:
	UIManager.pop_modal()

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

## Full-screen dim behind a modal.
##
## The scrim is the panel's SIBLING rather than a child drawn with
## show_behind_parent: a Container re-lays-out its Control children, and the
## panel's own entrance tween modulates its children, which would fade the dim
## back out from underneath the panel. As a sibling the draw order and the alpha
## are both unambiguous, and it dies with the panel.
##
## It goes to index 0 of the HUD layer, NOT directly under the panel. That is
## deliberate and load-bearing: modals do not pause the tree (UIManager only
## counts them — see ui_manager.gd), so while the console or the map is open the
## player is still walking around and enemies are still swinging. A scrim sitting
## directly under the panel covers the HUD too, and an 86% dim over the HP bar,
## the resource readout and the objective line means the player cannot see they
## are being killed. At index 0 the dim lands on the WORLD, the HUD draws over it
## at full strength, and the modal draws over both.
static func attach_scrim(panel: Control, alpha: float = SCRIM_ALPHA) -> ColorRect:
	if panel == null or not panel.is_inside_tree():
		return null
	var parent := panel.get_parent()
	if parent == null:
		return null
	var scrim := ColorRect.new()
	scrim.name = "%sScrim" % panel.name
	scrim.color = _GameTheme.with_alpha(SCRIM_TINT, alpha)
	# Below the HUD, so it must not eat clicks aimed at HUD controls; the modal
	# body itself is opaque and stops anything aimed at the panel.
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Must keep dimming while the tree is paused (a modal can be up over a pause).
	scrim.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(scrim)
	parent.move_child(scrim, 0)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kill := func() -> void:
		if is_instance_valid(scrim):
			scrim.queue_free()
	panel.tree_exiting.connect(kill, CONNECT_ONE_SHOT)
	return scrim

## The height a centre-anchored modal is allowed to be on this viewport.
static func fitted_height(panel: Control, want_h: float,
		top_pad: float = TOP_PAD, bottom_reserve: float = HUD_BOTTOM_RESERVE) -> float:
	var vh: float = panel.get_viewport_rect().size.y
	return minf(want_h, maxf(MIN_HEIGHT, vh - top_pad - bottom_reserve))

## Size a centre-anchored modal and centre it in the space the HUD is NOT using —
## below the top bar, above the ability bar. Nothing the player can click ends up
## on top of an ability slot, and nothing the player needs to read (tokens, HP,
## the cycle clock) ends up under the panel.
static func place_centred(panel: Control, want_h: float,
		top_pad: float = TOP_PAD, bottom_reserve: float = HUD_BOTTOM_RESERVE) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	var h := fitted_height(panel, want_h, top_pad, bottom_reserve)
	var shift: float = (top_pad - bottom_reserve) * 0.5
	panel.offset_top = -h * 0.5 + shift
	panel.offset_bottom = h * 0.5 + shift

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
