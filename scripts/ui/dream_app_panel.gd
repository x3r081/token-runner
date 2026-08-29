extends Control

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

const _ArchDiagram = preload("res://scripts/ui/arch_diagram.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _subtitle: Label = $Panel/Margin/VBox/Subtitle
@onready var _ship_btn: Button = $Panel/Margin/VBox/ShipBtn

var _diagram: Control
var _ship_pulse: Tween
var _first_populate := true

func _ready() -> void:
	_apply_theme()
	_setup_diagram()
	_populate()
	$Panel/Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Panel/Margin/VBox/ShipBtn.pressed.connect(_on_ship)
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
	add_theme_stylebox_override("panel", _GameTheme.dream_app_panel())
	_panel.add_theme_stylebox_override("panel", _GameTheme.dream_app_panel())
	_GameTheme.add_sheen(_panel, _GameTheme.with_alpha(_GameTheme.CYAN, 0.05), 8.0)
	_GameTheme.style_heading(_title, _GameTheme.CYAN, 26)
	var glow := _GameTheme.add_glow_layer(_title, 2.1)
	_GameTheme.pulse(glow, 1.3, 2.1, 3.2)
	_subtitle.add_theme_color_override("font_color", _GameTheme.accent_muted())
	$Panel/Margin/VBox/Totals.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
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
		var info := Label.new()
		var branch_name: String = DreamAppManager.upgrade_defs.get(branch, {}).get("display", branch)
		if next.is_empty():
			info.text = "%s: MAX — %s" % [branch_name, DreamAppManager.get_upgrade_name(branch)]
			info.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.ACID, 0.7))
		else:
			info.text = "%s [%d]: %s → %s" % [branch_name, tier, DreamAppManager.get_upgrade_name(branch), next.get("name", "?")]
			info.tooltip_text = next.get("description", "")
			info.add_theme_color_override("font_color", _GameTheme.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(info)
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
			_GameTheme.style_button(btn, _GameTheme.GOLD, 14)
			var b: String = branch
			btn.pressed.connect(func(): _purchase(b))
			h.add_child(btn)
		vbox.add_child(h)
	if _first_populate:
		# Rows cascade in once; refreshes after a purchase snap instantly.
		_GameTheme.stagger_rows(vbox, 0.05, 0.1)
		_first_populate = false
	var totals := DreamAppManager.get_totals()
	$Panel/Margin/VBox/Totals.text = "Features: %d | Stability: %d | Security: %d | Debt incoming: check HUD" % [totals.features, totals.stability, totals.security]

func _res_abbr(res: String) -> String:
	match res:
		"tokens": return "tk"
		"compute": return "cp"
		"api_credits": return "API"
		"reputation": return "rep"
		"context": return "ctx"
		_: return res

func _purchase(branch: String) -> void:
	if DreamAppManager.purchase(branch):
		AudioManager.play_sfx("upgrade")
		_populate()
		_update_ship_status()
		if is_instance_valid(_diagram):
			_diagram.refresh()

func _update_ship_status() -> void:
	var req := DreamAppManager.get_ship_requirements()
	var ready := GameManager.can_ship()
	var status: Label = $Panel/Margin/VBox/ShipStatus
	status.text = "Ship Ready: %s\nFeatures %d/%d | Stability %d/%d | Upgrades %d/%d | AI %d/%d | Infra %d/%d" % [
		"YES — hit Deploy in Localhost!" if ready else "Not yet",
		req.features.current, req.features.required,
		req.stability.current, req.stability.required,
		req.total_upgrades.current, req.total_upgrades.required,
		req.ai_tier.current, req.ai_tier.required,
		req.infra_tier.current, req.infra_tier.required,
	]
	status.add_theme_color_override("font_color",
		_GameTheme.ACID if ready else _GameTheme.TEXT_DIM)
	# Deploy button demands attention once it would actually work.
	if ready and _ship_pulse == null:
		_ship_pulse = _ship_btn.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ship_pulse.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_ship_pulse.tween_property(_ship_btn, "modulate", Color(1.35, 1.35, 1.3, 1.0), 0.7)
		_ship_pulse.tween_property(_ship_btn, "modulate", Color.WHITE, 0.7)

func _on_ship() -> void:
	if GameManager.can_ship():
		GameManager.trigger_victory()
		var v := preload("res://scenes/ui/victory_screen.tscn").instantiate()
		var scene := get_tree().current_scene
		if scene and scene.has_method("show_overlay"):
			scene.show_overlay(v)
		elif scene:
			scene.add_child(v)
		queue_free()
