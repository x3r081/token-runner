class_name BossHud
extends CanvasLayer
## Boss presentation: the name card, the health bar, the phase call-outs and the
## defeat stamp. Created and owned by EnemyBase when `is_boss` is set, so a boss
## carries its own UI and nothing else in the project has to know it exists.
##
## Layer 3: below the HUD (`hud.gd` HUD_LAYER = 4), the guide overlay (8), event
## popups (15) and dialogue (20) — a conversation, an incident ticket and the
## player's own readout all outrank a boss.
##
## ROUND 6 — ONE PANEL, ONE ACCENT, NO DARKENING.
##
## Round 5 announced a boss with: a radial scrim over the band, an overbright
## duplicated glow layer behind the title, two hairlines wiping outward from the
## centre, an additive accent vignette flaring around all four screen edges, an
## opaque near-VOID plate with a hot accent lip and an 18px tinted shadow halo, a
## gradient bar fill with a WHITE_HOT top edge, a red damage ghost, a white chip
## at the leading edge, and a frame that flashed to 1.7x on every phase. Eleven
## effects to say "this one hits harder".
##
## What it is now, per VISUAL_BIBLE_V2 LAW 8:
##   NAME CARD   one modal panel in the announcement band — BASE 96%, 1px LINE
##               border, radius 2, no shadow — with the boss name in the accent
##               and two SMALL dim lines. Fades in, fades out.
##   STATUS BAR  a plain plate, the name, the live percentage, an 8px bar with a
##               flat accent fill, an epithet and a phase chip.
##   NOTHING     else. No scrim, no edge flare, no glow, no letterboxing. The
##               HUD is never dimmed by a cinematic and the world is never
##               darkened to make our text legible — the panel does that.
##
## LANES (hud.gd's header owns the map; these are the two slots reserved here):
##   ANNOUNCEMENT BAND   y 222..(222+height), centred, BAND_W wide. Below the
##                       waypoint's guidance band, which ends at 190
##                       (objective_waypoint.gd GUIDE_BAND_BOTTOM).
##   STATUS FRAME        content y -176..-120, plate y -186..-110, centred.
##                       Clears the toast line (hud.gd TOAST_BOTTOM = -104), the
##                       ability slots (ABILITY_BAR_TOP = -64) and the key legend
##                       (-30..-10), and sits right of the objective line
##                       (x 28..788).
##
## Nothing here blocks input or pauses the tree — the player fights through all
## of it. The layer is PROCESS_MODE_ALWAYS and every tween is
## TWEEN_PAUSE_PROCESS, so opening a dialogue mid-entrance cannot freeze a card
## at full opacity on screen (HANDOVER §4.4, the black-curtain bug).

const BAR_W := 600.0
const BAR_H := 8.0
## Status frame: content box height, and the padding its backing plate adds.
const FRAME_H := 56.0
const FRAME_PAD := 14.0
## Announcement band, in pixels from the top of the screen. 222 and not 112:
## `objective_waypoint.gd` pins its chevron at MARGIN_TOP = 112 and hangs its
## readout inside GUIDE_BAND_TOP..GUIDE_BAND_BOTTOM (112..190), so everything
## down to 190 belongs to guidance.
const BAND_TOP := 222.0
const BAND_W := 720.0
## Name card height.
const ENTRANCE_H := 96.0
## How long the card holds before it fades. The whole entrance is 0.25 in +
## DWELL + 0.32 out and must stay inside EnemyBase's 2.2s `_intro_lock`; at 1.63
## it lands on 2.20 exactly. If `_intro_lock` moves, move this with it.
const ENTRANCE_DWELL := 1.63

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
## passes the live phase number (2, 3, 4), so read these with `phase - 1`.
const PHASE_BANNERS := [
	"",
	"PHASE 2 — escalated to the wider team",
	"PHASE 3 — a war room has been opened",
	"PHASE 4 — the postmortem has been pre-written",
]

## Short form for the persistent chip under the bar. The banner is the moment;
## the chip is the state you can still read ten seconds later. Same indexing.
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
var _track: ColorRect
var _fill: TextureRect
var _bar_name: Label
var _bar_sub: Label
var _pct: Label
var _phase_chip: Label
var _pips: Array[ColorRect] = []
var _fill_tween: Tween
var _shake_tween: Tween
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
	# One theme for the layer: the aliased font, the one panel style, the 1px
	# label shadow. Every label below then only says its size and its colour.
	_root.theme = GameTheme.create(accent)
	add_child(_root)
	_build_bar()
	_bar_root.modulate.a = 0.0

## Whenever the tree is paused a full-screen modal is up and there is nothing to
## read here, so the frame steps out of the way rather than showing through. It
## keeps animating while paused — nothing freezes half-faded (HANDOVER §4.4) —
## it is only hidden.
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
	# Re-tint everything the boss colour drives, not just the name label.
	_apply_accent()

## Stable per-boss incident number — the same gag the event popups file under.
## Decorative only: nothing depends on reading it.
func _inc_number() -> String:
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
	# Parked in the gap between the world and the HUD's bottom band. The plate
	# reaches 10px above and 10px below this box, so its lowest edge is -110 —
	# clear of the toast line at -104 and well clear of the ability slots at -64.
	_bar_root.offset_left = -BAR_W * 0.5
	_bar_root.offset_right = BAR_W * 0.5
	_bar_root.offset_top = -176.0
	_bar_root.offset_bottom = -176.0 + FRAME_H
	_root.add_child(_bar_root)

	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(BAR_W, FRAME_H)
	_bar_root.add_child(_frame)

	# Backing plate, on the modal rule. It used to be fully opaque near-VOID with
	# a hot accent lip and an 18px halo, on the argument that a world caption was
	# ghosting through it at 12%. A 96% panel with a hairline border is opaque
	# enough for that and stops announcing itself as a separate object.
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.position = Vector2(-FRAME_PAD, -10.0)
	_plate.size = Vector2(BAR_W + FRAME_PAD * 2.0, FRAME_H + 20.0)
	_frame.add_child(_plate)

	# Row 1 — name on the left, live percentage on the right. The percentage is
	# information, so it gets the same weight as the name.
	_bar_name = Label.new()
	_bar_name.text = boss_name
	_bar_name.add_theme_font_override("font", GameTheme.spaced_font(2))
	_bar_name.add_theme_font_size_override("font_size", GameTheme.BODY)
	_bar_name.add_theme_color_override("font_color", accent)
	_bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_name.position = Vector2(0, 0)
	_bar_name.size = Vector2(BAR_W - 90.0, 24.0)
	_frame.add_child(_bar_name)

	_pct = Label.new()
	_pct.text = "100%"
	_pct.add_theme_font_size_override("font_size", GameTheme.BODY)
	_pct.add_theme_color_override("font_color", GameTheme.TEXT)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pct.position = Vector2(BAR_W - 90.0, 0)
	_pct.size = Vector2(90.0, 24.0)
	_frame.add_child(_pct)

	_track = ColorRect.new()
	_track.color = GameTheme.with_alpha(GameTheme.VOID, 0.72)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.position = Vector2(0, 28)
	_track.size = Vector2(BAR_W, BAR_H)
	_frame.add_child(_track)

	_fill = TextureRect.new()
	_fill.texture = GameTheme.bar_gradient_texture(accent, GameTheme.hot_of(accent))
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(BAR_W, BAR_H)
	_track.add_child(_fill)

	# Phase gates at 75/50/25%. Kept in draining order (phase 2 first) so
	# `_flare_pip()` can index them straight off the phase number.
	_pips.clear()
	for k: float in [0.75, 0.5, 0.25]:
		var pip := ColorRect.new()
		pip.color = GameTheme.with_alpha(GameTheme.VOID, 0.9)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.position = Vector2(BAR_W * k - 1.0, 0.0)
		pip.size = Vector2(1, BAR_H)
		pip.z_index = 2
		_track.add_child(pip)
		_pips.append(pip)

	# Row 3 — epithet on the left, phase chip on the right.
	var sub := Label.new()
	sub.text = boss_sub
	sub.add_theme_font_size_override("font_size", GameTheme.SMALL)
	sub.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.position = Vector2(0, 40)
	sub.size = Vector2(BAR_W - 190.0, 16.0)
	sub.name = "BossSub"
	_frame.add_child(sub)
	_bar_sub = sub

	_phase_chip = Label.new()
	_phase_chip.text = ""
	_phase_chip.add_theme_font_size_override("font_size", GameTheme.SMALL)
	_phase_chip.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	_phase_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_phase_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_chip.position = Vector2(BAR_W - 190.0, 40)
	_phase_chip.size = Vector2(190.0, 16.0)
	_frame.add_child(_phase_chip)

	_apply_accent()

## The status frame's backing — the one modal panel style, nothing else.
func _plate_box() -> StyleBoxFlat:
	return GameTheme.panel_box(accent, 0.0)

## Re-tint everything the boss colour drives. Safe to call before or after the
## nodes exist; `setup()` calls it once the real tint is known.
func _apply_accent() -> void:
	if is_instance_valid(_plate):
		_plate.add_theme_stylebox_override("panel", _plate_box())
	if is_instance_valid(_fill):
		_fill.texture = GameTheme.bar_gradient_texture(accent, GameTheme.hot_of(accent))
	if is_instance_valid(_bar_name):
		_bar_name.add_theme_color_override("font_color", accent)

## Health, 0..1 of max. The fill moves in 0.22s and anything over 6% of the bar
## kicks the frame. The lagging red ghost and the white leading-edge chip are
## gone — the bar getting shorter is the readout.
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
	if lost >= 0.06:
		_shake(minf(7.0, 3.0 + lost * 30.0))

## The live percentage, and the colour that says how worried to be.
func _update_pct() -> void:
	if not is_instance_valid(_pct):
		return
	var pc := int(round(_frac * 100.0))
	if pc == 0 and _frac > 0.0:
		pc = 1
	_pct.text = "%d%%" % pc
	var col := GameTheme.TEXT
	if _frac <= 0.25:
		col = GameTheme.RED
	elif _frac <= 0.5:
		col = GameTheme.AMBER
	_pct.add_theme_color_override("font_color", col)

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

## A fresh, empty box in the reserved band. EVERY boss call-out goes through
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

## Centred band label. No outline: the theme's one-pixel shadow does the job, and
## a 4–7px outline on a 44px title is a black slab with letters cut out of it.
func _band_label(host: Control, text: String, size: int, col: Color,
		top: float, height: float, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if spacing > 0:
		l.add_theme_font_override("font", GameTheme.spaced_font(spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0, top)
	l.size = Vector2(BAND_W, height)
	host.add_child(l)
	return l

## A hairline under the name. Static — the outward wipe was motion for its own
## sake, and it is the only rule left on the card.
func _band_rule(host: Control, top: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.5
	r.anchor_right = 0.5
	r.offset_left = -140.0
	r.offset_right = 140.0
	r.offset_top = top
	r.offset_bottom = top + 1.0
	host.add_child(r)
	return r

## The full-screen accent flare is REMOVED. It brightened all four screen edges
## on every entrance, every phase and the kill — a post-effect on top of a
## post-effect stack the bible now caps at "invisible" (LAW 5). Kept as a no-op
## so the three call sites read the same as before.
func _flash_edges(strength: float) -> void:
	if strength <= 0.0:
		return

# ------------------------------------------------------------ entrance ----

## The name card fades in inside the reserved band, the status frame rises into
## place, the card fades out. Nothing covers the player and nothing touches a
## HUD lane.
##
## Length: 0.25 in + ENTRANCE_DWELL + 0.32 out = 2.20s, which is exactly
## EnemyBase's `_intro_lock`.
func play_entrance() -> void:
	if _entered or not is_instance_valid(_root):
		return
	_entered = true
	_card = _band(ENTRANCE_H)

	# One modal panel, centred in the band, sized to its own text.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -BAND_W * 0.5
	panel.offset_right = BAND_W * 0.5
	panel.offset_top = 0.0
	panel.offset_bottom = ENTRANCE_H
	panel.add_theme_stylebox_override("panel", GameTheme.panel_box(accent, 16.0))
	_card.add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	_card_line(col, "%s · SEVERITY: YES" % _inc_number(), GameTheme.SMALL,
		GameTheme.TEXT_DIM, 4)
	_card_line(col, boss_name, GameTheme.HEADING, accent, 3)
	_card_line(col, boss_sub, GameTheme.SMALL, GameTheme.TEXT_DIM, 0)

	# The frame rises into place rather than appearing: 10px of travel reads as
	# an arrival and is short enough not to be a distraction.
	if is_instance_valid(_frame):
		_frame.position = Vector2(0, 10.0)
	_card.modulate.a = 0.0

	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var tw := _tw()
	_entrance_tween = tw
	tw.tween_property(_card, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_bar_root, "modulate:a", 1.0, 0.30)
	if is_instance_valid(_frame):
		tw.parallel().tween_property(_frame, "position", Vector2.ZERO, 0.30) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(ENTRANCE_DWELL)
	tw.tween_property(_card, "modulate:a", 0.0, 0.32)
	tw.tween_callback(_clear_card)

func _card_line(host: Node, text: String, size: int, col: Color, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	if spacing > 0:
		l.add_theme_font_override("font", GameTheme.spaced_font(spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(l)
	return l

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
## The entrance owns the band for 2.2s and `_frame.position` for the first 0.30s
## of that. Anything that needs either before it is done has to cut it rather
## than draw over a card that is still mid-fade. Leaves the status frame settled
## and fully faded in, which is exactly where the entrance would have left it.
func _cancel_entrance() -> void:
	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null
	_clear_card()
	# Unconditional on purpose: these are where a COMPLETED entrance leaves
	# things, so running them when there was nothing to cancel is a no-op, and
	# running them when `play_entrance()` never fired is the difference between a
	# defeat draining a visible bar and draining an invisible one.
	if is_instance_valid(_bar_root):
		_bar_root.modulate.a = 1.0
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO

# -------------------------------------------------------------- phases ----

## One line in the announcement band, the gate that was just crossed lights up,
## and the chip under the bar updates so the phase is still readable long after
## the line is gone.
func announce_phase(phase_index: int) -> void:
	if not is_instance_valid(_root):
		return
	# `phase_index` is the LIVE phase (2, 3, 4), and both tables are written
	# phase-first — entry 0 is phase 1. Indexing them by the phase itself is off
	# by one, which is how the 75% gate printed phase 3's banner and phase 2's
	# was authored but unreachable. Read both with `phase - 1`.
	var phase := clampi(phase_index, 1, mini(PHASE_BANNERS.size(), PHASE_CHIPS.size()))
	var text: String = PHASE_BANNERS[phase - 1]
	if text.is_empty():
		return
	_phase = phase
	# One hit big enough to cross a gate inside EnemyBase's intro lock would
	# otherwise stack this line on the entrance card, in the same band.
	_cancel_entrance()

	var host := _band(30.0)
	var lbl := _band_label(host, text, GameTheme.BODY, GameTheme.TEXT, 0.0, 30.0, 3)
	lbl.modulate.a = 0.0

	var tw := _tw()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.05)
	tw.tween_property(host, "modulate:a", 0.0, 0.35)
	tw.tween_callback(host.queue_free)

	_flare_pip(phase)
	_shake(5.0)
	if is_instance_valid(_phase_chip):
		_phase_chip.text = PHASE_CHIPS[phase - 1]
	AudioManager.play_sfx("denied")

## The gate the boss just fell through lights up. Takes the LIVE phase number;
## `_pips` is stored in draining order, so phase 2 (the 75% gate) is pip 0.
func _flare_pip(phase_index: int) -> void:
	var i := phase_index - 2
	if i < 0 or i >= _pips.size():
		return
	# One big hit can skip a gate outright — EnemyBase jumps straight to the
	# phase the current HP implies — so light EVERY gate now behind the boss. A
	# dark 75% marker on a boss sitting at 20% is a lie about the bar.
	for j in i + 1:
		var passed: ColorRect = _pips[j]
		if is_instance_valid(passed):
			passed.color = GameTheme.with_alpha(GameTheme.TEXT, 0.8)

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

## Bar drains and the incident is formally closed in the announcement band. The
## joke is that the action-item count is honest.
func play_death() -> void:
	if not is_instance_valid(_root):
		return
	# The stamp goes in the announcement band; a card still fading in it would
	# read as two incidents at once. Also settles the frame and its alpha.
	_cancel_entrance()
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO
	_frac = 0.0
	_update_pct()
	if is_instance_valid(_phase_chip):
		_phase_chip.text = "RESOLVED"

	var host := _band(72.0)
	var stamp := _band_label(host, "INCIDENT CLOSED", GameTheme.HEADING,
		GameTheme.TEXT, 0.0, 34.0, 6)
	var rule := _band_rule(host, 38.0, GameTheme.with_alpha(accent, 0.7))
	var line := _band_label(host,
		"root cause: you · action items: 3 · completed: 0 · reopened next quarter: 3",
		GameTheme.SMALL, GameTheme.TEXT_DIM, 46.0, 22.0)
	stamp.modulate.a = 0.0
	rule.modulate.a = 0.0
	line.modulate.a = 0.0

	var tw := _tw()
	if is_instance_valid(_fill):
		tw.tween_property(_fill, "size:x", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(0.5)
	tw.tween_callback(_death_beat)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(rule, "modulate:a", 1.0, 0.30)
	tw.parallel().tween_property(line, "modulate:a", 1.0, 0.34)
	tw.tween_interval(1.4)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

## The impact frame of the defeat: the sound of a ticket being closed by someone
## who is not relieved. The white pop through the frame and the edge flare went
## with the rest of the effects.
func _death_beat() -> void:
	# NOT "achievement": AudioManager plays that stream on `achievement_unlocked`
	# (audio_manager._on_achievement_unlocked), and two achievements unlock on
	# boss kills specifically — `i_can_explain` (Merge Conflict) and
	# `context_is_social_construct` (Infinite Context) — so it would double-fire
	# on those and false-signal an unlock on every other boss. "upgrade" is the
	# only positive stinger with no signal binding: its other callers live inside
	# the Dream App panel, which cannot be open mid-fight.
	AudioManager.play_sfx("upgrade")

## Fade out and free without the stamp — used if the boss leaves any other way.
func dismiss() -> void:
	_cancel_entrance()
	if not is_instance_valid(_root):
		queue_free()
		return
	var tw := _tw()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
