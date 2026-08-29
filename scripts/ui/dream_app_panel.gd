extends Control
## The Dream App console: where tokens become features and features become debt.
## Every row states the real numbers first (tier, next upgrade, effective cost)
## and then says something unkind about it. The ship checklist is explicit —
## which requirement is met, which is not, and what to do about it.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

const _ArchDiagram = preload("res://scripts/ui/arch_diagram.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _subtitle: Label = $Panel/Margin/VBox/Subtitle
@onready var _ship_btn: Button = $Panel/Margin/VBox/ShipBtn

var _diagram: Control
var _ship_pulse: Tween
var _first_populate := true
var _base_subtitle := ""

func _ready() -> void:
	_apply_theme()
	_setup_diagram()
	_populate()
	$Panel/Margin/VBox/CloseBtn.text = "Close Console"
	$Panel/Margin/VBox/CloseBtn.tooltip_text = "Closes the console. [B] does the same thing, faster."
	$Panel/Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Panel/Margin/VBox/ShipBtn.pressed.connect(_on_ship)
	_ship_btn.tooltip_text = _Comedy.pick("ship_tip", _Comedy.SHIP_BTN_TIPS)
	_update_ship_status()
	_start_hologram_pulse()
	_GameTheme.open_panel(_panel)

## Live, procedurally-drawn architecture diagram that grows more ridiculous with
## every upgrade/decision (shown near the top of the panel).
func _setup_diagram() -> void:
	_diagram = _ArchDiagram.new()
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_child(_diagram)
	vbox.move_child(_diagram, 2)  # just under the subtitle
	_diagram.refresh()

func _apply_theme() -> void:
	var theme := _GameTheme.create()
	_panel.theme = theme
	# The console carries a diagram, a checklist and nine upgrade rows; give it
	# the room to say all of that without arguing with its own layout.
	_panel.offset_left = -460.0
	_panel.offset_right = 460.0
	_panel.offset_top = -440.0
	_panel.offset_bottom = 440.0
	var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
	scroll.custom_minimum_size = Vector2(0, 300)
	add_theme_stylebox_override("panel", _GameTheme.dream_app_panel())
	_panel.add_theme_stylebox_override("panel", _GameTheme.dream_app_panel())
	_GameTheme.add_sheen(_panel, _GameTheme.with_alpha(_GameTheme.CYAN, 0.05), 8.0)
	_GameTheme.style_heading(_title, _GameTheme.CYAN, 26)
	var glow := _GameTheme.add_glow_layer(_title, 2.1)
	_GameTheme.pulse(glow, 1.3, 2.1, 3.2)
	_base_subtitle = _Comedy.pick("dream_sub", _Comedy.DREAM_APP_SUBTITLES)
	_subtitle.text = _base_subtitle
	_subtitle.add_theme_color_override("font_color", _GameTheme.accent_muted())
	var totals_label: Label = $Panel/Margin/VBox/Totals
	totals_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	totals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ship_btn.add_theme_stylebox_override("normal", _GameTheme.ship_button())
	_ship_btn.add_theme_stylebox_override("hover", _GameTheme.ship_button())
	_ship_btn.add_theme_color_override("font_color", _GameTheme.accent_cyan())
	_GameTheme.attach_hover_motion(_ship_btn)
	_GameTheme.style_button($Panel/Margin/VBox/CloseBtn, _GameTheme.CYAN, 14)
	# Backdrop eases in so the world dims like a monitor waking up.
	var bd: ColorRect = $Backdrop
	bd.modulate.a = 0.0
	var bt := bd.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	bt.tween_property(bd, "modulate:a", 1.0, _GameTheme.T_STD)

func _start_hologram_pulse() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_panel, "modulate:a", 0.985, 1.4)
	tween.tween_property(_panel, "modulate:a", 1.0, 1.4)

func _populate() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox/Scroll/BranchList
	for c in vbox.get_children():
		c.queue_free()
	for branch in DreamAppManager.BRANCHES:
		var tier: int = DreamAppManager.get_branch_tier(branch)
		var next: Dictionary = DreamAppManager.get_next_upgrade(branch)
		var h: HBoxContainer = HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		# Left side is a two-line block: the facts, then the verdict.
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var info := Label.new()
		var branch_name: String = DreamAppManager.upgrade_defs.get(branch, {}).get("display", branch)
		if next.is_empty():
			info.text = "%s: MAX — %s" % [branch_name, DreamAppManager.get_upgrade_name(branch)]
			info.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.ACID, 0.7))
		else:
			info.text = "%s [%d]: %s → %s" % [branch_name, tier, DreamAppManager.get_upgrade_name(branch), next.get("name", "?")]
			info.tooltip_text = "%s\n\n%s" % [next.get("description", ""), _Comedy.branch_quip(branch)]
			info.add_theme_color_override("font_color", _GameTheme.TEXT)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(info)
		var quip := Label.new()
		if next.is_empty():
			quip.text = _Comedy.branch_quip(branch)
		else:
			quip.text = _next_note(next, branch)
		quip.add_theme_font_size_override("font_size", 11)
		quip.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.8))
		quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(quip)
		h.add_child(col)
		if not next.is_empty():
			var btn := Button.new()
			# Show the EFFECTIVE cost (debt + vendor price index), i.e. what is
			# actually charged — not the raw base cost.
			var cost: Dictionary = DreamAppManager.get_effective_cost(branch)
			var parts: Array = []
			for k in cost:
				parts.append("%d %s" % [int(cost[k]), _res_abbr(k)])
			btn.text = "Buy · %s" % ", ".join(parts)
			btn.disabled = not DreamAppManager.can_purchase(branch)
			var afford := "Affordable right now."
			if btn.disabled:
				afford = "You cannot afford this yet — go collect tokens."
			btn.tooltip_text = "Buys %s. %s" % [next.get("name", "the next tier"), afford]
			_GameTheme.style_button(btn, _GameTheme.GOLD, 14)
			var b: String = branch
			btn.pressed.connect(func(): _purchase(b))
			h.add_child(btn)
		vbox.add_child(h)
	if _first_populate:
		# Rows cascade in once; refreshes after a purchase snap instantly.
		_GameTheme.stagger_rows(vbox, 0.05, 0.1)
		_first_populate = false
	_update_totals()

## Second line of an upgrade row: the debt it adds (real number) plus the joke.
func _next_note(next: Dictionary, branch: String) -> String:
	var debt := int(next.get("debt", 0))
	if debt > 0:
		return "+%d technical debt · %s" % [debt, _Comedy.branch_quip(branch)]
	return _Comedy.branch_quip(branch)

## Totals row: the numbers, a verdict, and the one economy rule players miss —
## debt silently raises the price of everything you buy afterwards.
func _update_totals() -> void:
	var totals := DreamAppManager.get_totals()
	var surcharge := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))
	var verdict := "Balanced. For now."
	if totals.features == 0:
		verdict = "Zero features. The purest possible product."
	elif totals.security == 0 and totals.features >= 8:
		verdict = "Feature-rich and completely unguarded. A classic pairing."
	elif totals.stability <= 3:
		verdict = "Stability is, at this point, a rumour."
	elif totals.features >= 20:
		verdict = "More features than users. Traditional."
	elif surcharge >= 30:
		verdict = "The debt surcharge is now a bigger line item than the features."
	$Panel/Margin/VBox/Totals.text = "Features: %d | Stability: %d | Security: %d   —   %s\nPrices below already include your debt surcharge (+%d%%). Every upgrade adds debt; debt raises every future price." % [
		totals.features, totals.stability, totals.security, verdict, surcharge]

func _res_abbr(res: String) -> String:
	match res:
		"tokens": return "tk"
		"compute": return "cp"
		"api_credits": return "API"
		"reputation": return "rep"
		"context": return "ctx"
		_: return res

func _purchase(branch: String) -> void:
	var incoming: Dictionary = DreamAppManager.get_next_upgrade(branch)
	var debt := int(incoming.get("debt", 0))
	var bought: String = String(incoming.get("name", "it"))
	if DreamAppManager.purchase(branch):
		AudioManager.play_sfx("upgrade")
		_populate()
		_update_ship_status()
		if is_instance_valid(_diagram):
			_diagram.refresh()
		_confirm_purchase(bought, debt)

## Comedic receipt, in the subtitle slot, reverting after a few seconds. It
## always names what you bought and what it cost you in debt.
func _confirm_purchase(bought: String, debt: int) -> void:
	var line := "✔ %s — %s" % [bought, _Comedy.purchase_quip()]
	if debt > 0:
		line = "✔ %s  (+%d debt) — %s" % [bought, debt, _Comedy.debt_quip()]
	_subtitle.text = line
	_subtitle.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.GOLD))
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(3.4)
	t.tween_callback(func() -> void:
		if is_instance_valid(_subtitle):
			_subtitle.text = _base_subtitle
			_subtitle.add_theme_color_override("font_color", _GameTheme.accent_muted()))

## The ship checklist. Explicit ✓/✗ per requirement so "why can't I deploy" is
## answered without guesswork; the comedy sits in the header line only.
func _update_ship_status() -> void:
	var req := DreamAppManager.get_ship_requirements()
	var ready := GameManager.can_ship()
	var status: Label = $Panel/Margin/VBox/ShipStatus
	var rows: Array[String] = []
	var missing := 0
	for entry: Array in [
			["Features", req.features], ["Stability", req.stability],
			["Total upgrades", req.total_upgrades], ["AI tier", req.ai_tier],
			["Infrastructure tier", req.infra_tier]]:
		var d: Dictionary = entry[1]
		var ok: bool = int(d.current) >= int(d.required)
		var mark := "✓"
		if not ok:
			mark = "✗"
			missing += 1
		rows.append("  %s %s %d/%d" % [mark, String(entry[0]), int(d.current), int(d.required)])
	var header := ""
	if ready:
		header = "SHIP READY — press Deploy below, or walk to the Deploy button in Localhost.\nNothing is stopping you now except taste."
	else:
		var plural := "s"
		if missing == 1:
			plural = ""
		header = "NOT SHIPPABLE YET — %d requirement%s outstanding.\nBuy the upgrades marked ✗ below. Tokens come from pickups, quests and defeated bugs." % [missing, plural]
	status.text = "%s\n%s" % [header, "\n".join(rows)]
	status.add_theme_color_override("font_color",
		_GameTheme.ACID if ready else _GameTheme.TEXT_DIM)
	# Deploy button demands attention once it would actually work. It stays
	# pressable when it isn't — a dead button teaches nothing; a refusal does.
	if ready:
		_ship_btn.text = "▶ Deploy To Production"
	else:
		_ship_btn.text = "▶ Deploy To Production  (requirements not met)"
	if ready and _ship_pulse == null:
		_ship_pulse = _ship_btn.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ship_pulse.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_ship_pulse.tween_property(_ship_btn, "modulate", Color(1.35, 1.35, 1.3, 1.0), 0.7)
		_ship_pulse.tween_property(_ship_btn, "modulate", Color.WHITE, 0.7)

const _DENIALS := [
	"Deploy refused. The checklist above is not a suggestion.",
	"Denied. You cannot ship a ✗. We checked. Repeatedly.",
	"Blocked. Buy the missing upgrades first — the ✗ rows, specifically.",
	"No. And the button will keep saying no until the checklist is all ✓.",
]

func _on_ship() -> void:
	if not GameManager.can_ship():
		# Refuse loudly and usefully: restate the checklist and shake the panel.
		_update_ship_status()
		var status: Label = $Panel/Margin/VBox/ShipStatus
		status.text = "%s\n%s" % [_Comedy.pick("ship_denial", _DENIALS), status.text]
		status.add_theme_color_override("font_color", _GameTheme.AMBER)
		AudioManager.play_sfx("ui_click")
		# Amber flash instead of a shake: anchored containers fight positional
		# tweens, and the point is legibility, not drama.
		var t := status.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(status, "modulate", Color(1.6, 1.3, 0.7, 1.0), 0.08)
		t.tween_property(status, "modulate", Color.WHITE, 0.35)
		return
	if GameManager.can_ship():
		GameManager.trigger_victory()
		var v := preload("res://scenes/ui/victory_screen.tscn").instantiate()
		var scene := get_tree().current_scene
		if scene and scene.has_method("show_overlay"):
			scene.show_overlay(v)
		elif scene:
			scene.add_child(v)
		queue_free()
