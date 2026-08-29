class_name BossHud
extends CanvasLayer
## Boss presentation: the entrance name card, the health bar, phase banners and
## the death stamp. Created and owned by EnemyBase when `is_boss` is set, so a
## boss carries its own UI and nothing else in the project has to know it exists.
##
## Layer 3: above the HUD (1), below dialogue (10) and event popups (15), so a
## conversation or an incident ticket always wins.
##
## Everything is Tween-driven and null-safe. If the boss is freed mid-entrance
## the whole layer goes with it; `detach()` hands the layer to the current scene
## first when the death sequence needs to outlive the corpse.

const BAR_W := 600.0
const BAR_H := 16.0

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

const PHASE_BANNERS := [
	"",
	"PHASE 2 — escalated to the wider team",
	"PHASE 3 — a war room has been opened",
	"PHASE 4 — the postmortem has been pre-written",
]

var accent: Color = Color("#FF4757")
var boss_name: String = "BOSS"
var boss_sub: String = "severity: yes · owner: unassigned"

var _root: Control
var _card: Control
var _bar_root: Control
var _fill: TextureRect
var _ghost: ColorRect
var _bar_name: Label
var _bar_sub: Label
var _ghost_tween: Tween
var _fill_tween: Tween
var _entered := false
var _frac := 1.0

func _init() -> void:
	layer = 3

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_bar()
	_bar_root.modulate.a = 0.0

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
		_bar_name.add_theme_color_override("font_color", GameTheme.hot_of(accent))
	if is_instance_valid(_bar_sub):
		_bar_sub.text = boss_sub

# ------------------------------------------------------------- the bar ----

func _build_bar() -> void:
	_bar_root = Control.new()
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_root.anchor_left = 0.5
	_bar_root.anchor_right = 0.5
	_bar_root.anchor_top = 1.0
	_bar_root.anchor_bottom = 1.0
	# Parked above the ability bar (which owns the bottom 74px) and clear of the
	# bottom-left objective panel.
	_bar_root.offset_left = -BAR_W * 0.5
	_bar_root.offset_right = BAR_W * 0.5
	_bar_root.offset_top = -168.0
	_bar_root.offset_bottom = -100.0
	_root.add_child(_bar_root)

	_bar_name = Label.new()
	_bar_name.text = boss_name
	_bar_name.add_theme_font_override("font", GameTheme.spaced_font(3))
	_bar_name.add_theme_font_size_override("font_size", 17)
	_bar_name.add_theme_color_override("font_color", GameTheme.hot_of(accent))
	_bar_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_bar_name.add_theme_constant_override("outline_size", 5)
	_bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_name.anchor_right = 1.0
	_bar_name.offset_bottom = 24.0
	_bar_root.add_child(_bar_name)

	var track := ColorRect.new()
	track.color = Color(0.02, 0.03, 0.06, 0.88)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = Vector2(0, 30)
	track.size = Vector2(BAR_W, BAR_H)
	_bar_root.add_child(track)

	var edge := ColorRect.new()
	edge.color = Color(accent.r, accent.g, accent.b, 0.25)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.position = Vector2(-2, 28)
	edge.size = Vector2(BAR_W + 4, BAR_H + 4)
	edge.z_index = -1
	_bar_root.add_child(edge)

	# Damage ghost: a red segment that lags behind the real fill by half a second
	# so you can see exactly how much of that just came off.
	_ghost = ColorRect.new()
	_ghost.color = Color(1.0, 0.28, 0.34, 0.55)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.position = Vector2(0, 1)
	_ghost.size = Vector2(BAR_W, BAR_H - 2)
	track.add_child(_ghost)

	_fill = TextureRect.new()
	_fill.texture = GameTheme.bar_gradient_texture(accent, GameTheme.hot_of(accent))
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2(0, 1)
	_fill.size = Vector2(BAR_W, BAR_H - 2)
	track.add_child(_fill)

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

	# Phase pips at 75/50/25%.
	for k: float in [0.25, 0.5, 0.75]:
		var pip := ColorRect.new()
		pip.color = Color(0.02, 0.03, 0.06, 0.9)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.position = Vector2(BAR_W * k - 1.0, 0)
		pip.size = Vector2(2, BAR_H)
		pip.z_index = 2
		track.add_child(pip)

	var sub := Label.new()
	sub.text = boss_sub
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.anchor_right = 1.0
	sub.offset_top = 50.0
	sub.offset_bottom = 72.0
	sub.name = "BossSub"
	_bar_root.add_child(sub)
	_bar_sub = sub

## Health, 0..1 of max. The fill snaps in 0.22s; the ghost follows half a second
## later, which is what makes a big hit feel big.
func set_health(current: int, maximum: int) -> void:
	if not is_instance_valid(_fill):
		return
	var f := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	_frac = f
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_property(_fill, "size:x", BAR_W * f, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_ghost):
		if _ghost_tween and _ghost_tween.is_valid():
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.35)
		_ghost_tween.tween_property(_ghost, "size:x", BAR_W * f, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

# ------------------------------------------------------------ entrance ----

## Letterbox in, name card wipes on, bar slides up. ~2.4s end to end and it
## never blocks input — the player can move the whole time.
func play_entrance() -> void:
	if _entered or not is_instance_valid(_root):
		return
	_entered = true
	var bars: Array[ColorRect] = []
	for k: float in [0.0, 1.0]:
		var b := ColorRect.new()
		b.color = Color(0.01, 0.01, 0.03, 0.92)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.anchor_left = 0.0
		b.anchor_right = 1.0
		b.anchor_top = k
		b.anchor_bottom = k
		if k == 0.0:
			b.offset_bottom = 0.0
		else:
			b.offset_top = 0.0
		_root.add_child(b)
		bars.append(b)

	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.anchor_left = 0.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.36
	_card.anchor_bottom = 0.36
	_root.add_child(_card)

	var rule := ColorRect.new()
	rule.color = Color(accent.r * 2.0, accent.g * 2.0, accent.b * 2.0, 0.95)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.anchor_left = 0.5
	rule.anchor_right = 0.5
	rule.offset_left = 0.0
	rule.offset_right = 0.0
	rule.offset_top = -14.0
	rule.offset_bottom = -12.0
	_card.add_child(rule)

	var title := Label.new()
	title.text = boss_name
	title.add_theme_font_override("font", GameTheme.spaced_font(6))
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", GameTheme.WHITE_HOT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 4.0
	title.offset_bottom = 64.0
	_card.add_child(title)
	GameTheme.add_glow_layer(title, 2.4)

	var sub := Label.new()
	sub.text = boss_sub
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.anchor_left = 0.0
	sub.anchor_right = 1.0
	sub.offset_top = 66.0
	sub.offset_bottom = 92.0
	_card.add_child(sub)

	title.modulate.a = 0.0
	sub.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(bars[0], "offset_bottom", 84.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bars[1], "offset_top", -84.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The accent rule wipes outward from the centre — the "reveal" beat.
	tw.tween_property(rule, "offset_left", -230.0, 0.34).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule, "offset_right", 230.0, 0.34).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(title, "modulate:a", 1.0, 0.3)
	tw.tween_property(sub, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_bar_root, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.15)
	tw.tween_property(_card, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(bars[0], "offset_bottom", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bars[1], "offset_top", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_clear_card.bind(bars))

func _clear_card(bars: Array) -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	for b in bars:
		if is_instance_valid(b):
			b.queue_free()

# -------------------------------------------------------------- phases ----

## Banner + a colour beat on the bar. Called on each phase threshold crossing.
func announce_phase(phase_index: int) -> void:
	if not is_instance_valid(_root):
		return
	var text: String = PHASE_BANNERS[clampi(phase_index, 0, PHASE_BANNERS.size() - 1)]
	if text.is_empty():
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", GameTheme.spaced_font(4))
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", GameTheme.WHITE_HOT)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.30
	lbl.anchor_bottom = 0.30
	lbl.offset_bottom = 40.0
	_root.add_child(lbl)
	lbl.modulate = Color(1, 1, 1, 0)
	lbl.scale = Vector2(1.14, 1.14)
	lbl.pivot_offset = Vector2(_center_x(), 18.0)
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(lbl.queue_free)
	if is_instance_valid(_bar_name):
		var flash := create_tween()
		flash.tween_property(_bar_name, "modulate", Color(2.4, 2.4, 2.4, 1.0), 0.08)
		flash.tween_property(_bar_name, "modulate", Color.WHITE, 0.45)

# --------------------------------------------------------------- death ----

## Horizontal centre of the screen. Read from the viewport rather than from a
## Control's `size`, which can still be zero on the frame after a reparent.
func _center_x() -> float:
	var vp := get_viewport()
	if vp:
		return vp.get_visible_rect().size.x * 0.5
	return 640.0

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

## Bar drains, then the incident is closed with a stamp. The joke is that the
## action-item count is honest.
func play_death() -> void:
	if not is_instance_valid(_root):
		return
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _ghost_tween and _ghost_tween.is_valid():
		_ghost_tween.kill()
	var stamp := Label.new()
	stamp.text = "INCIDENT CLOSED"
	stamp.add_theme_font_override("font", GameTheme.spaced_font(8))
	stamp.add_theme_font_size_override("font_size", 40)
	stamp.add_theme_color_override("font_color", GameTheme.WHITE_HOT)
	stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	stamp.add_theme_constant_override("outline_size", 8)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.anchor_left = 0.0
	stamp.anchor_right = 1.0
	stamp.anchor_top = 0.38
	stamp.anchor_bottom = 0.38
	stamp.offset_bottom = 56.0
	_root.add_child(stamp)
	GameTheme.add_glow_layer(stamp, 2.6)

	var line := Label.new()
	line.text = "root cause: you · action items: 3 · completed: 0"
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	line.add_theme_constant_override("outline_size", 5)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.38
	line.anchor_bottom = 0.38
	line.offset_top = 58.0
	line.offset_bottom = 82.0
	_root.add_child(line)

	stamp.scale = Vector2(2.4, 2.4)
	stamp.pivot_offset = Vector2(_center_x(), 26.0)
	stamp.modulate.a = 0.0
	line.modulate.a = 0.0

	if is_instance_valid(_ghost):
		var gt := create_tween()
		gt.tween_property(_ghost, "size:x", 0.0, 0.75).set_trans(Tween.TRANS_CUBIC)
	var tw := create_tween()
	if is_instance_valid(_fill):
		tw.tween_property(_fill, "size:x", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(0.5)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.12)
	tw.tween_property(line, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.5)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

## Fade out and free without the stamp — used if the boss leaves any other way.
func dismiss() -> void:
	if not is_instance_valid(_root):
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
