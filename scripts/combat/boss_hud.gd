class_name BossHud
extends CanvasLayer
## Boss presentation: the announcement band (entrance card, phase call-outs, the
## defeat stamp) and the status frame (name, live %, health bar, epithet, phase
## chip). Created and owned by EnemyBase when `is_boss` is set, so a boss
## carries its own UI and nothing else in the project has to know it exists.
##
## Layer 3: below the HUD (`hud.gd` HUD_LAYER = 4), the guide overlay (8), event
## popups (15) and dialogue (20), so a conversation or an incident ticket always
## wins — and so does the player's own readout.
##
## ROUND 5 — THE HUD IS NOT OURS TO DRAW ON.
## The round-4 entrance letterboxed the top and bottom of the screen, which
## dimmed the resource bar and the ability bar, and dropped a 46px name card on
## screen centre — exactly where the player is standing and fighting. Both are
## gone. Layer order alone does not fix that: a full-screen dim under the HUD
## still eats the world the player is fighting in, and the name card still lands
## on the player. Everything now lives in one of two reserved slots inside the
## HUD's free space (lanes per the header of `scripts/ui/hud.gd`):
##
##   ANNOUNCEMENT BAND   y 222..360, centred, BAND_W wide.
##                       Below StatusStrip (ends 90..122), left of the toast
##                       rail (starts ~W-396), ~57px above the player's head
##                       (measured — see ROUND 6 note 2, NOT the 105px an
##                       earlier draft of this header claimed).
##   STATUS FRAME        content y -218..-140, plate y -230..-130, centred,
##                       BAR_W + 2*FRAME_PAD wide. Clears AbilityBar
##                       (hud.gd ABILITY_BAR_TOP = -100.0, so 30px of gap; the
##                       plate's 18px stylebox shadow halo reaches -112, still
##                       12px clear) and HintBar (-34..-12), sits right of
##                       QuestPanel (x 24..434) and left of the minimap
##                       (x W-220..W-24).
##
## READING A QA FRAME. Every number in this file is in CANVAS units. The QA
## capture runs a 1920x928 window against a 1920x1080 base with stretch
## `canvas_items` + aspect `expand`, so the canvas is 2234.5 x 1080 and the PNG
## is that canvas at scale 0.85926 (= 928/1080). canvas = image_px / 0.85926.
## Verified against this file's own geometry: the plate's left edge measures
## image x 687 = canvas 799.5 against a predicted 799.24, and the round-5
## entrance rule measured image y 146 = canvas 170 against a coded 170. Do not
## measure a frame as if it were 1920x1080 — the code is not 25px wrong.
##
## ROUND 6 — CLEARANCE. Two things in the round-5 QA frames were still wrong,
## and both were "our pixels and somebody else's pixels in the same place":
##
##  1. `region_cloud_district.png` — the plate was `glass_box` untouched, BASE at
##     88%. The world caption "Egress fees apply / to leaving. And to thinking."
##     sat behind it and its second line ghosted through under the boss name and
##     the "100%". Measured off the frame: that line peaks at RGB sum 744 where
##     it clears the plate and at 86 where it does not — 12% transmission,
##     exactly as coded. So it is a faint ghost, not the "grey mud" an earlier
##     draft of this header called it, but it is still legible text crawling
##     under a combat readout, and a boss bar is the one surface in the game that
##     has to be unambiguous. The plate is now FULLY OPAQUE with a hot accent lip
##     along its top edge, so it is a UI object with a stated boundary.
##
##     Two things this does NOT fix, both of them world-text's side of the line:
##     the caption's FIRST line sits at y 834..850 against a plate top of 850 and
##     survives (dimmed by the plate's shadow halo), and the caption runs to
##     x ~1463 while the plate ends at 1435, so ~28px of its tail still shows
##     past the plate's right edge. `y -230..-130`, x centre +-318 is the band
##     world text is expected to dodge; the opaque plate braces that band, it
##     does not replace it.
##
##  2. `region_token_vault.png` — the entrance card's kicker (y 144..162) and its
##     first rule (y 170) landed straight on the objective waypoint, which pins
##     its chevron at `objective_waypoint.gd` MARGIN_TOP = 138 and hangs its
##     "Localhost · 13m / through this portal" readout 46px under it. That
##     readout is at most TWO lines — `_update_label_text()` never writes a third
##     — and it is centred on its anchor, so its worst case is anchor 138+46=184
##     with a 36px box: y 166..202. Measured off the frame it lands at 165..201.
##     Guidance owns y 119..202.
##
##     BAND_TOP therefore starts at 222 (20px of real gap; the kicker's first ink
##     is at 226), and the entrance card was tightened from 152px to 138px so the
##     84px of descent costs nothing at the bottom: the card now ends at y 360.
##     The player's head measures canvas y ~417 in both round-5 frames (canvas
##     height is >= 1080 under `expand`, so screen centre is >= 540 and the
##     sprite's top is ~115 above it) — so the clearance is ~57px, NOT the 105px
##     an earlier draft of this header claimed. It is real clearance, but it is
##     the tighter of the two ends: buy margin at the top out of the bottom only
##     down to about BAND_TOP 240, and re-measure a frame before going further.
##
##     Known and accepted: at 222..360 the band now lands on the region prop
##     cards ("THE CLOUD", "THE RESERVES", both ~y 285..372) instead of on the
##     waypoint. That trade is deliberate — the waypoint is permanent guidance
##     and the prop cards are decorative flavour, and the band only exists for
##     2.2s with a scrim behind it. Guidance stays readable; nothing lands on
##     the player.
##
## Nothing here blocks input or pauses the tree — the player fights through all
## of it. The layer is PROCESS_MODE_ALWAYS and every tween is
## TWEEN_PAUSE_PROCESS, so opening a dialogue mid-entrance can no longer freeze
## a card at full opacity on screen (HANDOVER §4.4, the black-curtain bug).
##
## Everything is Tween-driven and null-safe. If the boss is freed mid-entrance
## the whole layer goes with it; `detach()` hands the layer to the current scene
## first when the death sequence needs to outlive the corpse.

const BAR_W := 600.0
const BAR_H := 18.0
## Status frame: content box height, and the padding its backing plate adds.
const FRAME_H := 78.0
const FRAME_PAD := 18.0
## Announcement band, in pixels from the top of the screen. 222 and not 138:
## `objective_waypoint.gd` pins its chevron at MARGIN_TOP = 138 and hangs an
## up-to-three-line readout under it, so y 119..214 belongs to guidance.
const BAND_TOP := 222.0
const BAND_W := 1040.0
## Entrance card height. Trimmed with the descent to BAND_TOP so the card still
## ends well clear of the player — see the ROUND 6 note in the header.
const ENTRANCE_H := 138.0
## How long the entrance card holds before it fades. See `play_entrance()` — the
## whole entrance is 1.50s + this, and must stay inside EnemyBase's `_intro_lock`.
const ENTRANCE_DWELL := 0.70

## Comedy bible: the joke rides ALONGSIDE the information. The name is the
## information (which boss is this), the subtitle is the joke.
const BOSS_CARDS := {
	"merge_conflict": ["THE MERGE CONFLICT", "1,204 files changed · nobody remembers why"],
	"enterprise_architect": ["THE ENTERPRISE ARCHITECT", "has never merged a pull request"],
	"legacy_monolith": ["THE LEGACY MONOLITH", "written in 2009 · load-bearing · undocumented"],
	"legacy_system": ["THE LEGACY SYSTEM", "runs the payroll. do not touch the payroll."],
	"infinite_context": ["THE INFINITE CONTEXT", "remembers everything except the point"],
	"cloud_bill": ["THE $700 CLOUD BILL", "mostly egress. nobody can explain egress."],
	"dependency_demon": ["THE DEPENDENCY DEMON", "14,203 packages · three of them on purpose"],
	"scope_creep": ["SCOPE CREEP", "and one tiny last thing"],
	"hallucination": ["THE HALLUCINATION", "100% confident · 0% sourced"],
	"rate_limiter": ["THE RATE LIMITER", "429. try again in a period we won't specify."],
	"memory_leak": ["THE MEMORY LEAK", "it has been growing since Tuesday"],
	"null_reference": ["THE NULL REFERENCE", "cannot read properties of undefined"],
	"bug": ["THE BUG", "reproducible only when observed"],
}

## Indexed by PHASE - 1: entry 0 is phase 1, which announces nothing. EnemyBase
## passes the live phase number (2, 3, 4 — `_check_boss_phase`), so read these
## with `phase - 1`, never with `phase`.
const PHASE_BANNERS := [
	"",
	"PHASE 2 — escalated to the wider team",
	"PHASE 3 — a war room has been opened",
	"PHASE 4 — the postmortem has been pre-written",
]

## Short form for the persistent chip under the bar. The banner is the moment;
## the chip is the state you can still read ten seconds later. Same indexing as
## PHASE_BANNERS: PHASE - 1.
const PHASE_CHIPS := [
	"",
	"PHASE 2 · ESCALATED",
	"PHASE 3 · WAR ROOM",
	"PHASE 4 · POSTMORTEM",
]

var accent: Color = Color("#FF4757")
var boss_name: String = "BOSS"
var boss_sub: String = "severity: yes · owner: unassigned"

var _root: Control
var _card: Control
var _bar_root: Control
## Everything inside the status frame hangs off this, so damage can shake the
## whole frame without fighting the anchors that keep it out of the HUD's lanes.
var _frame: Control
var _plate: Panel
## Hot accent lip along the plate's top edge: the line that tells the eye where
## the UI starts and the world stops.
var _plate_lip: ColorRect
var _edge: ColorRect
var _track: ColorRect
var _fill: TextureRect
var _ghost: ColorRect
var _bar_name: Label
var _bar_sub: Label
var _pct: Label
var _phase_chip: Label
var _pips: Array[ColorRect] = []
var _ghost_tween: Tween
var _fill_tween: Tween
var _shake_tween: Tween
var _pct_tween: Tween
## The phase flash and the death beat both drive `_frame.modulate`. Tracked so
## a kill landing right after a phase crossing cannot have the flash's 0.45s
## return-to-white overwrite the cold tint the defeat just set.
var _flash_tween: Tween
## The entrance's own tween, tracked so anything that needs the announcement
## band back (a phase call, the defeat stamp, `dismiss()`) can cut the card
## instead of stamping on top of one that is still mid-fade.
var _entrance_tween: Tween
var _entered := false
var _frac := 1.0
var _phase := 1

func _init() -> void:
	layer = 3
	# A boss card that freezes at full opacity because someone opened a dialogue
	# mid-entrance is a screen-covering bug, not a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_bar()
	_bar_root.modulate.a = 0.0

## Whenever the tree is paused a full-screen modal is up (pause menu, quest log,
## Dream App, map, event ticket, dialogue) and there is nothing to read here, so
## the frame steps out of the way rather than showing through. It keeps
## animating while paused — nothing freezes half-faded (HANDOVER §4.4) — it is
## only hidden. Toggling `_root` rather than the CanvasLayer's own `visible`
## keeps this on a Control property every other overlay in the project uses.
func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null or not is_instance_valid(_root):
		return
	var want := not tree.paused
	if _root.visible != want:
		_root.visible = want

## Every tween on this layer survives `get_tree().paused` — see the header.
func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t

## Called by EnemyBase before the entrance plays.
func setup(enemy_type: String, tint: Color) -> void:
	accent = tint
	var card: Array = BOSS_CARDS.get(enemy_type, [])
	if card.size() == 2:
		boss_name = str(card[0])
		boss_sub = str(card[1])
	else:
		boss_name = enemy_type.replace("_", " ").to_upper()
		boss_sub = "severity: yes · owner: unassigned"
	if is_instance_valid(_bar_name):
		_bar_name.text = boss_name
	if is_instance_valid(_bar_sub):
		_bar_sub.text = boss_sub
	# The frame is built before setup() runs, so it is built in the DEFAULT red.
	# Round 4 only re-tinted the name label, which is why every boss bar in the
	# QA frames drained the same production-incident red regardless of species.
	_apply_accent()

## Stable per-boss incident number — the same gag the event popups file under.
## Decorative only: nothing depends on reading it.
func _inc_number() -> String:
	# Same derivation as `event_popup.gd:_ticket()`, so the two incident surfaces
	# number tickets the same way.
	return "INC-%04d" % (absi(boss_name.hash()) % 9000 + 1000)

# ------------------------------------------------------------- the bar ----

func _build_bar() -> void:
	_bar_root = Control.new()
	_bar_root.name = "StatusFrame"
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_root.anchor_left = 0.5
	_bar_root.anchor_right = 0.5
	_bar_root.anchor_top = 1.0
	_bar_root.anchor_bottom = 1.0
	# Parked in the gap between the world and the HUD's bottom console. The
	# backing plate reaches 12px above and 22px below this box, so its lowest edge
	# is -130 — 30px clear of hud.gd's ABILITY_BAR_TOP, which is -100.0, not the
	# -104 an earlier revision of this comment claimed. The plate's 18px stylebox
	# shadow halo reaches -112, so the real gap is 12px of falloff. Horizontally
	# it sits between the objective panel and the minimap. Lane map in the header.
	_bar_root.offset_left = -BAR_W * 0.5
	_bar_root.offset_right = BAR_W * 0.5
	_bar_root.offset_top = -218.0
	_bar_root.offset_bottom = -218.0 + FRAME_H
	_root.add_child(_bar_root)

	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(BAR_W, FRAME_H)
	_bar_root.add_child(_frame)

	# Backing plate: the frame reads as one object over any floor, and its dark
	# halo is what separates the bar from a bright gold vault slab. OPAQUE — see
	# `_plate_box()` and the ROUND 6 note in the header.
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.position = Vector2(-FRAME_PAD, -12.0)
	_plate.size = Vector2(BAR_W + FRAME_PAD * 2.0, FRAME_H + 22.0)
	_frame.add_child(_plate)

	# Inset by the plate's corner radius so the lip lands on the straight run of
	# the top edge instead of poking out past the rounded corners.
	_plate_lip = ColorRect.new()
	_plate_lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_lip.position = Vector2(-FRAME_PAD + 8.0, -12.0)
	_plate_lip.size = Vector2(BAR_W + FRAME_PAD * 2.0 - 16.0, 2.0)
	_frame.add_child(_plate_lip)

	# Row 1 — name on the left, live percentage on the right. The percentage is
	# information, so it gets the same weight as the name.
	_bar_name = Label.new()
	_bar_name.text = boss_name
	_bar_name.add_theme_font_override("font", GameTheme.spaced_font(3))
	_bar_name.add_theme_font_size_override("font_size", 18)
	_bar_name.add_theme_color_override("font_color", GameTheme.hot_of(accent))
	_bar_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_bar_name.add_theme_constant_override("outline_size", 5)
	_bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_name.position = Vector2(0, 0)
	_bar_name.size = Vector2(BAR_W - 110.0, 24.0)
	_frame.add_child(_bar_name)

	_pct = Label.new()
	_pct.text = "100%"
	_pct.add_theme_font_override("font", GameTheme.spaced_font(2))
	_pct.add_theme_font_size_override("font_size", 18)
	_pct.add_theme_color_override("font_color", GameTheme.WHITE_HOT)
	_pct.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_pct.add_theme_constant_override("outline_size", 5)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pct.position = Vector2(BAR_W - 110.0, 0)
	_pct.size = Vector2(110.0, 24.0)
	_frame.add_child(_pct)

	_edge = ColorRect.new()
	_edge.color = Color(accent.r, accent.g, accent.b, 0.30)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.position = Vector2(-3, 27)
	_edge.size = Vector2(BAR_W + 6, BAR_H + 6)
	_frame.add_child(_edge)

	_track = ColorRect.new()
	_track.color = Color(0.02, 0.03, 0.06, 0.92)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.position = Vector2(0, 30)
	_track.size = Vector2(BAR_W, BAR_H)
	_frame.add_child(_track)

	# Damage ghost: a red segment that lags behind the real fill by a third of a
	# second so you can see exactly how much of that just came off.
	_ghost = ColorRect.new()
	_ghost.color = Color(1.0, 0.28, 0.34, 0.55)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.position = Vector2(0, 1)
	_ghost.size = Vector2(BAR_W, BAR_H - 2)
	_track.add_child(_ghost)

	_fill = TextureRect.new()
	_fill.texture = GameTheme.bar_gradient_texture(accent, GameTheme.hot_of(accent))
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2(0, 1)
	_fill.size = Vector2(BAR_W, BAR_H - 2)
	_track.add_child(_fill)

	# 1px WHITE_HOT top edge (bible: bars get a hot lip). Anchored so it tracks
	# the fill as it drains instead of hanging off the end.
	var lip := ColorRect.new()
	lip.color = Color(1.6, 1.7, 1.8, 0.7)
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip.anchor_right = 1.0
	lip.offset_left = 0.0
	lip.offset_right = 0.0
	lip.offset_top = 0.0
	lip.offset_bottom = 1.0
	_fill.add_child(lip)

	# Phase gates at 75/50/25%. Kept in draining order (phase 2 first) so
	# `_flare_pip()` can index them straight off the phase number.
	_pips.clear()
	for k: float in [0.75, 0.5, 0.25]:
		var pip := ColorRect.new()
		pip.color = Color(0.02, 0.03, 0.06, 0.9)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.position = Vector2(BAR_W * k - 1.0, -2.0)
		pip.size = Vector2(2, BAR_H + 4.0)
		pip.z_index = 2
		_track.add_child(pip)
		_pips.append(pip)

	# Row 3 — epithet on the left, phase chip on the right.
	var sub := Label.new()
	sub.text = boss_sub
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.position = Vector2(0, 54)
	sub.size = Vector2(BAR_W - 190.0, 22.0)
	sub.name = "BossSub"
	_frame.add_child(sub)
	_bar_sub = sub

	_phase_chip = Label.new()
	_phase_chip.text = ""
	_phase_chip.add_theme_font_override("font", GameTheme.spaced_font(2))
	_phase_chip.add_theme_font_size_override("font_size", 12)
	_phase_chip.add_theme_color_override("font_color", GameTheme.hot_of(accent))
	_phase_chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_phase_chip.add_theme_constant_override("outline_size", 4)
	_phase_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_phase_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_chip.position = Vector2(BAR_W - 190.0, 54)
	_phase_chip.size = Vector2(190.0, 22.0)
	_frame.add_child(_phase_chip)

	_apply_accent()

## The status frame's backing.
##
## Round 5 handed this to `GameTheme.glass_box` unchanged — BASE at 88% — and in
## `region_cloud_district.png` the world caption "Egress fees apply / to leaving.
## And to thinking." sat behind it, its second line ghosting through under the
## boss name and the percentage at the coded 12% (measured: RGB sum 744 clear of
## the plate, 86 behind it). Faint, but it is readable text crawling under the
## one readout in the game that has to be unambiguous. So: fully opaque,
## near-VOID rather than BASE (so nothing about it can be mistaken for floor), an
## accent-lerped border, and a bigger, darker accent-tinted drop shadow — the
## shadow is what keeps the transition to the world soft, which is what stops an
## opaque plate from reading as a rectangle pasted over the frame.
##
## The bible (VISUAL_BIBLE §UI: "Panels: BASE bg at 92% alpha") is deliberately
## overridden HERE and only here. It costs nothing visually: the graded frame
## already renders the 88% plate's interior at RGB (0,0,2), and this bg is
## (5,7,14) before grading, so the plate does not get heavier — the ghost just
## stops. Do not copy this to a general panel.
func _plate_box() -> StyleBoxFlat:
	var s := GameTheme.glass_box(accent, 0.0)
	s.bg_color = Color(0.020, 0.026, 0.055, 1.0)
	s.border_color = GameTheme.with_alpha(accent.lerp(GameTheme.LINE, 0.45), 0.9)
	s.shadow_color = GameTheme.with_alpha(accent.lerp(GameTheme.VOID, 0.72), 0.66)
	s.shadow_size = 18
	return s

## Re-tint everything the boss colour drives. Safe to call before or after the
## nodes exist; `setup()` calls it once the real tint is known.
func _apply_accent() -> void:
	var hot := GameTheme.hot_of(accent)
	if is_instance_valid(_plate):
		_plate.add_theme_stylebox_override("panel", _plate_box())
	if is_instance_valid(_plate_lip):
		_plate_lip.color = GameTheme.with_alpha(hot, 0.85)
	if is_instance_valid(_edge):
		_edge.color = Color(accent.r, accent.g, accent.b, 0.30)
	if is_instance_valid(_fill):
		_fill.texture = GameTheme.bar_gradient_texture(accent, hot)
	if is_instance_valid(_bar_name):
		_bar_name.add_theme_color_override("font_color", hot)
	if is_instance_valid(_phase_chip):
		_phase_chip.add_theme_color_override("font_color", hot)

## Health, 0..1 of max. The fill snaps in 0.22s; the ghost follows a third of a
## second later, which is what makes a big hit feel big. A white chip marks the
## new leading edge, and anything over 6% of the bar kicks the frame.
func set_health(current: int, maximum: int) -> void:
	if not is_instance_valid(_fill):
		return
	var f := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	var lost := maxf(0.0, _frac - f)
	_frac = f
	_update_pct()
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = _tw()
	_fill_tween.tween_property(_fill, "size:x", BAR_W * f, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_ghost):
		if _ghost_tween and _ghost_tween.is_valid():
			_ghost_tween.kill()
		_ghost_tween = _tw()
		_ghost_tween.tween_interval(0.35)
		_ghost_tween.tween_property(_ghost, "size:x", BAR_W * f, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if lost > 0.0:
		_chip_edge(BAR_W * f)
	if lost >= 0.06:
		_shake(minf(9.0, 3.0 + lost * 36.0))

## The live percentage, and the colour that says how worried to be. Numbers
## first — the player must be able to read this at a glance mid-fight.
func _update_pct() -> void:
	if not is_instance_valid(_pct):
		return
	var pc := int(round(_frac * 100.0))
	if pc == 0 and _frac > 0.0:
		pc = 1
	_pct.text = "%d%%" % pc
	var col := GameTheme.WHITE_HOT
	if _frac <= 0.25:
		col = GameTheme.RED
	elif _frac <= 0.5:
		col = GameTheme.AMBER
	_pct.add_theme_color_override("font_color", col)
	if _pct_tween and _pct_tween.is_valid():
		_pct_tween.kill()
	_pct.modulate = Color(1.9, 1.9, 1.9, 1.0)
	_pct_tween = _tw()
	_pct_tween.tween_property(_pct, "modulate", Color.WHITE, 0.28)

## White sliver at the new leading edge of the fill: the "that landed" tell.
func _chip_edge(x: float) -> void:
	if not is_instance_valid(_track):
		return
	var chip := ColorRect.new()
	chip.color = Color(1.9, 1.9, 2.0, 0.95)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.position = Vector2(maxf(0.0, x - 3.0), 0.0)
	chip.size = Vector2(5.0, BAR_H)
	chip.z_index = 3
	_track.add_child(chip)
	var tw := _tw()
	tw.tween_property(chip, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(chip.queue_free)

## Kick the whole status frame sideways. Only the frame moves — the anchors that
## keep it out of the HUD's lanes are untouched.
func _shake(px: float) -> void:
	if not is_instance_valid(_frame):
		return
	# The entrance owns `_frame.position` while it rises. Two tweens on the same
	# property is how you get a bar that never settles.
	if is_instance_valid(_card):
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_frame.position = Vector2.ZERO
	_shake_tween = _tw()
	for i in 3:
		var d: float = px * (1.0 - float(i) / 3.0)
		if i % 2 == 1:
			d = -d
		_shake_tween.tween_property(_frame, "position:x", d, 0.045)
	_shake_tween.tween_property(_frame, "position", Vector2.ZERO, 0.07)

# ---------------------------------------------------- announcement band ----

## A fresh, empty panel in the reserved band. EVERY boss call-out goes through
## here, which is what guarantees none of them can land on the player or on a
## HUD lane.
func _band(height: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -BAND_W * 0.5
	c.offset_right = BAND_W * 0.5
	c.offset_top = BAND_TOP
	c.offset_bottom = BAND_TOP + height
	_root.add_child(c)
	return c

## Soft elliptical scrim behind band text. Radial, so it has no hard edge — a
## letterbox rectangle is exactly the "texture patch pasted on" read this round
## is trying to kill everywhere else in the game.
func _scrim(host: Control, height: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	# Deeper than round 5's 0.80/0.56: over the Token Vault's lit gold slab the
	# card's epithet row was fighting the floor for contrast. Still a radial
	# falloff to zero, so there is no hard edge anywhere.
	g.colors = PackedColorArray([
		Color(0.01, 0.01, 0.03, 0.88),
		Color(0.01, 0.01, 0.03, 0.66),
		Color(0.01, 0.01, 0.03, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 64
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# +40 of bleed each side keeps the falloff soft while staying inside the
	# 1920-unit minimum canvas width, clear of the toast rail at ~W-396.
	tr.position = Vector2(-40.0, -18.0)
	tr.size = Vector2(BAND_W + 80.0, height + 36.0)
	tr.modulate.a = 0.0
	host.add_child(tr)
	return tr

## Centred band label. Outline scales with the size so 46px titles stay legible
## over a neon floor without turning into a black slab at 12px.
func _band_label(host: Control, text: String, size: int, col: Color,
		top: float, height: float, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if spacing > 0:
		l.add_theme_font_override("font", GameTheme.spaced_font(spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0, top)
	l.size = Vector2(BAND_W, height)
	host.add_child(l)
	return l

## Hairline that wipes outward from the centre — the reveal beat.
func _band_rule(host: Control, top: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.5
	r.anchor_right = 0.5
	r.offset_left = 0.0
	r.offset_right = 0.0
	r.offset_top = top
	r.offset_bottom = top + 2.0
	host.add_child(r)
	return r

## Accent flare around the screen edges. It BRIGHTENS for a third of a second —
## it never dims, so the HUD stays readable through it.
func _flash_edges(strength: float) -> void:
	if not is_instance_valid(_root):
		return
	var vig := GameTheme.make_vignette(GameTheme.with_alpha(GameTheme.hot_of(accent), 0.9))
	vig.material = GameTheme.additive_material()
	vig.modulate.a = 0.0
	_root.add_child(vig)
	_root.move_child(vig, 0)
	var tw := _tw()
	tw.tween_property(vig, "modulate:a", strength, 0.10)
	tw.tween_property(vig, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(vig.queue_free)

# ------------------------------------------------------------ entrance ----

## Ticket number, rule wipe, name, epithet, then the status frame rises. It never
## blocks input, and every pixel of it sits in the reserved band — nothing covers
## the player and nothing touches a HUD lane.
##
## Length, step by step, because it has to fit inside EnemyBase's 2.2s
## `_intro_lock`: 0.20 scrim + 0.34 rules + 0.30 title + 0.34 epithet/frame-rise
## + DWELL + 0.32 card fade = 1.50 + DWELL. DWELL is 0.70, so 2.20s exactly. If
## `_intro_lock` moves, move DWELL with it.
func play_entrance() -> void:
	if _entered or not is_instance_valid(_root):
		return
	_entered = true
	_card = _band(ENTRANCE_H)
	var scrim := _scrim(_card, ENTRANCE_H)

	var hot := GameTheme.hot_of(accent)
	# Rows, tightened from round 5's 6/32/40/106/140 over 152px. The card lost
	# 14px of height and 2pt off the title so that descending past the waypoint's
	# lane (header, ROUND 6) costs nothing at the bottom of the band.
	var kicker := _band_label(_card, "%s · SEVERITY: YES · REPORTED BY: EVERYONE" % _inc_number(),
		13, GameTheme.with_alpha(hot, 0.85), 4.0, 18.0, 6)
	var rule := _band_rule(_card, 30.0, Color(accent.r * 2.0, accent.g * 2.0, accent.b * 2.0, 0.95))
	var title := _band_label(_card, boss_name, 44, GameTheme.WHITE_HOT, 38.0, 60.0, 6)
	GameTheme.add_glow_layer(title, 2.4)
	var sub := _band_label(_card, boss_sub, 17, GameTheme.TEXT_DIM, 100.0, 26.0)
	var rule2 := _band_rule(_card, 128.0, GameTheme.with_alpha(hot, 0.55))

	kicker.modulate.a = 0.0
	title.modulate.a = 0.0
	title.pivot_offset = Vector2(BAND_W * 0.5, 30.0)
	title.scale = Vector2(1.06, 0.92)
	sub.modulate.a = 0.0
	sub.position.y += 8.0

	# The frame rises into place rather than appearing: 18px of travel is enough
	# to read as an arrival and short enough not to be a distraction.
	if is_instance_valid(_frame):
		_frame.position = Vector2(0, 18.0)

	_flash_edges(0.30)

	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var tw := _tw()
	_entrance_tween = tw
	tw.tween_property(scrim, "modulate:a", 1.0, 0.20)
	tw.parallel().tween_property(kicker, "modulate:a", 1.0, 0.20)
	tw.tween_property(rule, "offset_left", -300.0, 0.28).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule, "offset_right", 300.0, 0.28).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule2, "offset_left", -220.0, 0.34).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule2, "offset_right", 220.0, 0.34).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(title, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(sub, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(sub, "position:y", 100.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_bar_root, "modulate:a", 1.0, 0.34)
	if is_instance_valid(_frame):
		tw.parallel().tween_property(_frame, "position", Vector2.ZERO, 0.34) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(ENTRANCE_DWELL)
	tw.tween_property(_card, "modulate:a", 0.0, 0.32)
	tw.tween_callback(_clear_card)

## The last beat of the entrance. `queue_free()` is deferred to the end of the
## frame, so hide it in the same call — a card the tween has finished with must
## not be able to paint one more frame at whatever alpha it happens to hold.
func _clear_card() -> void:
	if is_instance_valid(_card):
		_card.visible = false
		_card.queue_free()
	_card = null

## Take the announcement band back NOW.
##
## The entrance owns the band for 2.2s and `_frame.position` for the first 0.34s
## of that. Anything that needs either before it is done — a phase crossing, the
## defeat stamp, `dismiss()` — has to cut it rather than draw over a card that is
## still mid-fade, or the band ends up with two stacked call-outs and the frame
## with two tweens fighting over its position. Leaves the status frame settled
## and fully faded in, which is exactly where the entrance would have left it.
func _cancel_entrance() -> void:
	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null
	_clear_card()
	# Unconditional on purpose: these are where a COMPLETED entrance leaves
	# things, so running them when there was nothing to cancel is a no-op, and
	# running them when `play_entrance()` never fired at all is the difference
	# between a defeat draining a visible bar and draining an invisible one.
	if is_instance_valid(_bar_root):
		_bar_root.modulate.a = 1.0
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO

# -------------------------------------------------------------- phases ----

## Banner in the announcement band, a flare on the gate that was just crossed,
## a hot pulse through the frame, and the chip under the bar updates so the
## phase is still readable long after the banner is gone.
func announce_phase(phase_index: int) -> void:
	if not is_instance_valid(_root):
		return
	# `phase_index` is the LIVE phase (2, 3, 4), and both tables are written
	# phase-first — entry 0 is phase 1. Indexing them by the phase itself was off
	# by one: the 75% gate printed "PHASE 3 — a war room has been opened",
	# "PHASE 2 — escalated to the wider team" was authored but could never be
	# reached, and phase 4 clamped back onto phase 3's banner so the 25% gate
	# never lit its pip. Read both with `phase - 1`.
	var phase := clampi(phase_index, 1, mini(PHASE_BANNERS.size(), PHASE_CHIPS.size()))
	var text: String = PHASE_BANNERS[phase - 1]
	if text.is_empty():
		return
	_phase = phase
	# One hit big enough to cross a gate inside EnemyBase's intro lock would
	# otherwise stack this banner on the entrance card, in the same band.
	_cancel_entrance()
	var hot := GameTheme.hot_of(accent)

	var host := _band(58.0)
	var scrim := _scrim(host, 58.0)
	var rule := _band_rule(host, 0.0, Color(hot.r * 1.5, hot.g * 1.5, hot.b * 1.5, 0.9))
	var lbl := _band_label(host, text, 27, GameTheme.WHITE_HOT, 10.0, 40.0, 4)
	lbl.modulate.a = 0.0
	lbl.pivot_offset = Vector2(BAND_W * 0.5, 20.0)
	lbl.scale = Vector2(1.12, 1.12)

	var tw := _tw()
	tw.tween_property(scrim, "modulate:a", 1.0, 0.14)
	tw.parallel().tween_property(rule, "offset_left", -260.0, 0.26).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule, "offset_right", 260.0, 0.26).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.05)
	tw.tween_property(host, "modulate:a", 0.0, 0.35)
	tw.tween_callback(host.queue_free)

	_flash_edges(0.22)
	_flare_pip(phase)
	_shake(6.0)
	if is_instance_valid(_phase_chip):
		_phase_chip.text = PHASE_CHIPS[phase - 1]
		_phase_chip.modulate = Color(2.2, 2.2, 2.2, 1.0)
		var chip_tw := _tw()
		chip_tw.tween_property(_phase_chip, "modulate", Color.WHITE, 0.5)
	if is_instance_valid(_frame):
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_tween = _tw()
		_flash_tween.tween_property(_frame, "modulate", Color(1.7, 1.7, 1.7, 1.0), 0.09)
		_flash_tween.tween_property(_frame, "modulate", Color.WHITE, 0.45)
	AudioManager.play_sfx("denied")

## The gate the boss just fell through lights up and burns out. Takes the LIVE
## phase number; `_pips` is stored in draining order, so phase 2 (the 75% gate)
## is pip 0, phase 3 is pip 1, phase 4 is pip 2.
func _flare_pip(phase_index: int) -> void:
	var i := phase_index - 2
	if i < 0 or i >= _pips.size():
		return
	# One big hit can skip a gate outright — EnemyBase jumps straight to the phase
	# the current HP implies — so light EVERY gate now behind the boss, not just
	# this one. A dark 75% marker on a boss sitting at 20% is a lie about the bar.
	for j in i + 1:
		var passed: ColorRect = _pips[j]
		if is_instance_valid(passed):
			passed.color = Color(accent.r * 1.6, accent.g * 1.6, accent.b * 1.6, 0.95)
	var pip: ColorRect = _pips[i]
	if not is_instance_valid(pip):
		return
	var flare := ColorRect.new()
	flare.color = Color(1.9, 1.9, 2.0, 0.9)
	flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flare.position = Vector2(pip.position.x - 3.0, -8.0)
	flare.size = Vector2(8.0, BAR_H + 16.0)
	flare.z_index = 4
	if is_instance_valid(_track):
		_track.add_child(flare)
		var tw := _tw()
		tw.tween_property(flare, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC)
		tw.tween_callback(flare.queue_free)

# --------------------------------------------------------------- death ----

## Hand this layer to the current scene so the outro survives the corpse.
func detach() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var host: Node = tree.current_scene
	var p := get_parent()
	if host == null or host == self or p == null or p == host:
		return
	p.remove_child(self)
	host.add_child(self)

## Bar drains, the frame goes cold, and the incident is formally closed in the
## announcement band. The joke is that the action-item count is honest.
func play_death() -> void:
	if not is_instance_valid(_root):
		return
	# The stamp goes in the announcement band; a card still fading in it would
	# read as two incidents at once. Also settles the frame and its alpha.
	_cancel_entrance()
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _ghost_tween and _ghost_tween.is_valid():
		_ghost_tween.kill()
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	# A phase crossing seconds before the kill leaves a 0.45s return-to-white
	# running on `_frame.modulate`; the defeat's cold tint has to win.
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO
	_frac = 0.0
	_update_pct()
	if is_instance_valid(_phase_chip):
		_phase_chip.text = "RESOLVED"

	var host := _band(120.0)
	var scrim := _scrim(host, 120.0)
	var stamp := _band_label(host, "INCIDENT CLOSED", 44, GameTheme.WHITE_HOT, 6.0, 58.0, 8)
	GameTheme.add_glow_layer(stamp, 2.6)
	var rule := _band_rule(host, 68.0, GameTheme.with_alpha(GameTheme.hot_of(accent), 0.8))
	var line := _band_label(host,
		"root cause: you · action items: 3 · completed: 0 · reopened next quarter: 3",
		15, GameTheme.TEXT_DIM, 78.0, 24.0)

	stamp.scale = Vector2(2.2, 2.2)
	stamp.pivot_offset = Vector2(BAND_W * 0.5, 29.0)
	stamp.modulate.a = 0.0
	line.modulate.a = 0.0
	scrim.modulate.a = 0.0

	if is_instance_valid(_ghost):
		var gt := _tw()
		gt.tween_property(_ghost, "size:x", 0.0, 0.75).set_trans(Tween.TRANS_CUBIC)
	var tw := _tw()
	if is_instance_valid(_fill):
		tw.tween_property(_fill, "size:x", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(0.5)
	tw.tween_callback(_death_beat)
	tw.parallel().tween_property(scrim, "modulate:a", 1.0, 0.18)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.12)
	tw.tween_property(rule, "offset_left", -300.0, 0.30).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule, "offset_right", 300.0, 0.30).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(line, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

## The impact frame of the defeat: edge flare, a white pop through the status
## frame, and the sound of a ticket being closed by someone who is not relieved.
func _death_beat() -> void:
	_flash_edges(0.34)
	# NOT "achievement": AudioManager plays that stream on `achievement_unlocked`
	# (audio_manager._on_achievement_unlocked), and two achievements unlock on
	# boss kills specifically — `i_can_explain` (Merge Conflict) and
	# `context_is_social_construct` (Infinite Context) — so it would double-fire
	# on those and false-signal an unlock on every other boss. "upgrade" is the
	# only positive stinger with no signal binding: its other callers live inside
	# the Dream App panel, which cannot be open mid-fight.
	AudioManager.play_sfx("upgrade")
	if is_instance_valid(_frame):
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_tween = _tw()
		_flash_tween.tween_property(_frame, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.10)
		_flash_tween.tween_property(_frame, "modulate", Color(0.7, 0.72, 0.8, 1.0), 0.6)

## Fade out and free without the stamp — used if the boss leaves any other way.
func dismiss() -> void:
	_cancel_entrance()
	if not is_instance_valid(_root):
		queue_free()
		return
	var tw := _tw()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
