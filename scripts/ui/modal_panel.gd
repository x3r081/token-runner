extends Control
## Mixin-style helpers for modal panels that block random events, plus the
## shared "take over the screen properly" kit every screen-covering modal uses.
##
## Round 5 filed the Dream App console, the World Map and the Quest Log as
## unreadable: all three drew semi-transparently over a fully-lit, animated world
## with no dim behind them, so world labels, NPC nameplates and sprites punched
## straight through the panel body and collided with the text on top of it. The
## rules that came out of that live here so all three modals obey the same ones:
##
##   * a real SCRIM behind the panel — the world recedes, it does not compete;
##   * a panel body opaque enough that nothing from the world reads through
##     (0.92 is not enough: a neon caption still burns through 8%);
##   * a row reveal whose TOTAL duration is bounded, so a long list never reads
##     as a list that fades toward invisibility down the page;
##   * geometry that stays out of the band the HUD's ability bar owns.
##
## Panels stay neon-glass: near-opaque body, accent border, accent glow. Opaque
## is the readability floor, not the art direction.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

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

## Modal bodies are near-opaque on purpose. See the class docs.
const BODY_ALPHA := 0.985
const SCRIM_ALPHA := 0.86
const SCRIM_TINT := Color(0.012, 0.016, 0.038, 1.0)

func register_modal() -> void:
	UIManager.push_modal()
	tree_exiting.connect(_unregister_modal, CONNECT_ONE_SHOT)

func _unregister_modal() -> void:
	UIManager.pop_modal()

# ------------------------------------------------------------ shared kit ----

## Neon-glass body for a screen-covering modal: near-opaque BASE fill, accent
## border, accent outer glow. Same silhouette as GameTheme.panel_box(), enough
## fill behind it that a world caption cannot read through.
## (Accent is required, not defaulted: a default that reaches into another
## script's constants is one parse error away from taking this whole class down,
## and a dead class here would silently kill every modal that preloads it.)
static func modal_box(accent: Color, margin: float) -> StyleBoxFlat:
	var s := _GameTheme.panel_box(accent, margin)
	s.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, BODY_ALPHA)
	s.border_color = _GameTheme.with_alpha(accent, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.shadow_color = _GameTheme.with_alpha(accent, 0.22)
	s.shadow_size = 18
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
## the resource readout and the objective panel means the player cannot see they
## are being killed. At index 0 the dim lands on the WORLD, the HUD draws over it
## at full strength, and the modal draws over both. That is the whole hierarchy
## the round-5 critique asked for, without switching the vitals off.
static func attach_scrim(panel: Control, alpha: float = SCRIM_ALPHA) -> ColorRect:
	if panel == null or not panel.is_inside_tree():
		return null
	var parent := panel.get_parent()
	if parent == null:
		return null
	var scrim := ColorRect.new()
	scrim.name = "%sScrim" % panel.name
	scrim.color = _GameTheme.with_alpha(SCRIM_TINT, 0.0)
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
	var t := scrim.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(scrim, "color:a", alpha, _GameTheme.T_STD)
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

## Bounded row cascade.
##
## GameTheme.stagger_rows() delays each row by a FIXED step, so the map's 20 rows
## were still arriving nearly a second in and the list read as one that dims
## toward invisibility down the page — the bottom half looked like empty panel.
## Here the whole cascade is squeezed into `window` seconds however many rows
## there are, so the last row is up in ~0.3s and every row ends at full alpha.
static func reveal_rows(container: Node, window: float = 0.20) -> void:
	if container == null:
		return
	var rows: Array[Control] = []
	for c in container.get_children():
		if c is Control and (c as Control).visible:
			rows.append(c as Control)
	if rows.is_empty():
		return
	var step: float = window / float(rows.size())
	for i in rows.size():
		var ctrl: Control = rows[i]
		ctrl.modulate.a = 0.0
		var t := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(step * float(i))
		t.tween_property(ctrl, "modulate:a", 1.0, _GameTheme.T_MICRO)
