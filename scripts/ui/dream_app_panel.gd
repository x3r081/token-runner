extends Control
## The Dream App console: where tokens become features and features become debt.
## Every row states the real numbers first and then says one unkind thing about
## it. The ship checklist is explicit — which requirement is met, which is not.
##
## Round 6 removed the console's costume: the cyan-bordered "hologram" panel, its
## outer glow, the moving sheen quad, the title's duplicated glow layer and its
## breathing pulse, the alpha "breath" tween on the panel body (a two-round bug
## source — the panel is simply opaque now), the row cascade, the Deploy button's
## attention pulse, and about 40% of the words. What is left is a shop with
## prices in it.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

const _ArchDiagram = preload("res://scripts/ui/arch_diagram.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _subtitle: Label = $Panel/Margin/VBox/Subtitle
@onready var _ship_btn: Button = $Panel/Margin/VBox/ShipBtn

var _diagram: Control
var _wallet: Label
var _base_subtitle := ""

## Currencies upgrades are actually priced in (data/upgrades/dream_app.json).
## The HUD carries tokens and compute only, so the console has to say the rest.
const _WALLET_RESOURCES: Array[String] = ["tokens", "compute", "api_credits", "reputation"]

func _ready() -> void:
	_apply_theme()
	_setup_diagram()
	_populate()
	$Panel/Margin/VBox/CloseBtn.text = "Close"
	$Panel/Margin/VBox/CloseBtn.tooltip_text = "Closes the console. [B] does the same thing, faster."
	$Panel/Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Panel/Margin/VBox/ShipBtn.pressed.connect(_on_ship)
	_ship_btn.tooltip_text = _Comedy.pick("ship_tip", _Comedy.SHIP_BTN_TIPS)
	_update_ship_status()
	_GameTheme.open_panel(_panel)

## Live, procedurally-drawn architecture diagram that grows more ridiculous with
## every upgrade/decision (shown near the top of the panel).
func _setup_diagram() -> void:
	_diagram = _ArchDiagram.new()
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_child(_diagram)
	vbox.move_child(_diagram, 2)  # just under the subtitle
	# The diagram is the only decorative element in a panel that is otherwise all
	# guidance, and it was claiming 178px of a column whose minimums already
	# overflowed the panel — which is how the Close button ended up shoved down
	# into the HUD's ability bar. It gets 156: the lowest thing it draws is the
	# INFRA box at y140 + 11 half-height = y151, so nothing is clipped.
	#
	# Measured against the height ModalPanel actually granted the panel, not
	# against the viewport: with stretch mode "canvas_items" + aspect "expand" the
	# viewport is never shorter than 1080 whatever the window is, so a viewport
	# test here would be a branch that can never fire. If the reserved HUD bands
	# ever squeeze the column this hard, the gag is what goes — the ship checklist
	# and the upgrade prices are the reason anyone opened this screen.
	_diagram.custom_minimum_size = Vector2(470, 156)
	if (_panel.offset_bottom - _panel.offset_top) < 700.0:
		_diagram.visible = false
	_diagram.refresh()

func _apply_theme() -> void:
	var theme := _GameTheme.create()
	_panel.theme = theme
	# The console carries a diagram, a checklist and nine upgrade rows; give it
	# the room to say all of that without arguing with its own layout.
	_panel.offset_left = -460.0
	_panel.offset_right = 460.0
	# Height and vertical placement come from the modal kit, which keeps the panel
	# clear of both bands the HUD owns. Hard-coded ±440 drew "Close Console"
	# straight on top of ability slot 3 — the bar is MOUSE_FILTER_IGNORE so the
	# click still reached the button, but the frame showed "Close Console" and
	# "Rubber Duck" printed over each other, which is worse: the player cannot
	# tell what they are about to press.
	_Modal.place_centred(_panel, 900.0)
	# The column's minimum heights have to ADD UP to less than the panel, or the
	# VBox lays its tail out past the bottom edge — which is exactly what pushed
	# "Close Console" onto ability slot 3. Tighter margins and separation buy that
	# room back; the scroll keeps only a floor and takes the slack via EXPAND_FILL.
	var margin: MarginContainer = $Panel/Margin
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	var col: VBoxContainer = $Panel/Margin/VBox
	col.add_theme_constant_override("separation", 6)
	var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
	scroll.custom_minimum_size = Vector2(0, 120)
	# This is a SHOP and upgrades are priced in four currencies (tokens, compute,
	# API credits, reputation) while the HUD only carries two — so "Buy · 41 API"
	# was unanswerable without closing the console. The wallet line sits directly
	# above the buy list, in the same abbreviations the buttons use.
	_wallet = Label.new()
	_wallet.name = "Wallet"
	_wallet.add_theme_font_size_override("font_size", _Modal.SMALL)
	_wallet.add_theme_color_override("font_color", _GameTheme.TEXT)
	col.add_child(_wallet)
	col.move_child(_wallet, scroll.get_index())
	_panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 18.0))
	# One ACCENT on this screen: the title and the Deploy button. Everything else
	# is TEXT or TEXT_DIM, including the nine Buy buttons — a shop where every row
	# is gold is a shop with no hierarchy.
	_title.add_theme_color_override("font_color", _GameTheme.CYAN)
	_base_subtitle = _Comedy.pick("dream_sub", _Comedy.DREAM_APP_SUBTITLES)
	_subtitle.text = _base_subtitle
	_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var totals_label: Label = $Panel/Margin/VBox/Totals
	totals_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	totals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_GameTheme.style_button(_ship_btn, _GameTheme.CYAN, _Modal.BODY)
	_GameTheme.style_button($Panel/Margin/VBox/CloseBtn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	# The dim is split in two: a ModalPanel scrim at the BOTTOM of the HUD layer
	# (the world recedes, the HP bar and cycle clock do not — this console does
	# not pause the game), plus the authored Backdrop as a light tint over the HUD.
	_Modal.attach_scrim(self)

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
			info.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		else:
			info.text = "%s [%d]  →  %s" % [branch_name, tier, next.get("name", "?")]
			info.tooltip_text = "%s\n\n%s" % [next.get("description", ""), _Comedy.branch_quip(branch)]
			info.add_theme_color_override("font_color", _GameTheme.TEXT)
		info.add_theme_font_size_override("font_size", _Modal.BODY)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(info)
		var quip := Label.new()
		if next.is_empty():
			quip.text = _Comedy.branch_quip(branch)
		else:
			quip.text = _next_note(next, branch)
		quip.add_theme_font_size_override("font_size", _Modal.SMALL)
		quip.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
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
			_GameTheme.style_button(btn, _GameTheme.TEXT_DIM, _Modal.SMALL)
			var b: String = branch
			btn.pressed.connect(func(): _purchase(b))
			h.add_child(btn)
		vbox.add_child(h)
	_Modal.reveal_rows(vbox)
	_update_totals()

## Second line of an upgrade row: the debt it adds (real number) plus the joke.
func _next_note(next: Dictionary, branch: String) -> String:
	var debt := int(next.get("debt", 0))
	if debt > 0:
		return "+%d debt · %s" % [debt, _Comedy.branch_quip(branch)]
	return _Comedy.branch_quip(branch)

## Totals row: the numbers, then the one economy rule players miss — debt
## silently raises the price of everything bought afterwards.
func _update_totals() -> void:
	var totals := DreamAppManager.get_totals()
	var surcharge := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))
	$Panel/Margin/VBox/Totals.text = "Features %d · Stability %d · Security %d\nPrices include your debt surcharge (+%d%%); every upgrade adds more." % [
		totals.features, totals.stability, totals.security, surcharge]
	_update_wallet()
	_enforce_column_budget.call_deferred()

## Last-resort budget guard, measured instead of estimated.
##
## A Control never draws smaller than its minimum size, so if the column's
## minimum heights still add up to more than the panel was granted, the VBox lays
## its tail out PAST the bottom edge and "Close" lands on the ability bar.
## Deferred because an autowrapped label only knows its real wrapped height once
## it has been given a width. Nothing here can shrink guidance, so the decoration
## goes: the architecture gag is the only row nobody needs to read. One-way by
## design (it can hide, never re-show), so it cannot oscillate.
func _enforce_column_budget() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_diagram):
		return
	if not _diagram.visible:
		return
	var col: VBoxContainer = $Panel/Margin/VBox
	# Granted height, not size.y: if the column has already overflowed, size.y IS
	# the overflow and the test would pass while the panel hangs off the bottom.
	# 24 = Margin top+bottom (12 each), 36 = the modal box's content margin.
	var budget: float = (_panel.offset_bottom - _panel.offset_top) - 24.0 - 36.0
	if col.get_combined_minimum_size().y > budget:
		_diagram.visible = false

## What you can actually spend, in the same abbreviations the Buy buttons use.
## Refreshed with the totals (open + every purchase) rather than off
## ResourceManager.resource_changed: focus regenerates every frame and that
## signal fires with it, which would rebuild these strings 60 times a second.
func _update_wallet() -> void:
	if not is_instance_valid(_wallet):
		return
	var parts: Array[String] = []
	for res: String in _WALLET_RESOURCES:
		parts.append("%d %s" % [int(ResourceManager.get_value(res)), _res_abbr(res)])
	_wallet.text = "You have  %s" % "  ·  ".join(parts)

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
	else:
		AudioManager.play_sfx("denied")

## Comedic receipt, in the subtitle slot, reverting after a few seconds. It
## always names what you bought and what it cost you in debt.
func _confirm_purchase(bought: String, debt: int) -> void:
	var line := "%s — %s" % [bought, _Comedy.purchase_quip()]
	if debt > 0:
		line = "%s (+%d debt) — %s" % [bought, debt, _Comedy.debt_quip()]
	_subtitle.text = line
	_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(3.4)
	t.tween_callback(func() -> void:
		if is_instance_valid(_subtitle):
			_subtitle.text = _base_subtitle
			_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM))

## The ship checklist. Explicit ✓/✗ per requirement so "why can't I deploy" is
## answered without guesswork; one line of framing above it, not three.
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
		header = "SHIPPABLE — press Deploy, or walk to the Deploy button in Localhost."
	else:
		var plural := "s"
		if missing == 1:
			plural = ""
		header = "NOT SHIPPABLE — %d requirement%s left. Buy the ✗ rows below." % [missing, plural]
	status.text = "%s\n%s" % [header, "\n".join(rows)]
	status.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# The button stays pressable when it would refuse — a dead button teaches
	# nothing; a refusal does. It no longer pulses for attention: it is the only
	# accent-coloured control in the panel, which is attention enough.
	if ready:
		_ship_btn.text = "Deploy To Production"
	else:
		_ship_btn.text = "Deploy To Production  (not yet)"

const _DENIALS := [
	"Deploy refused. The checklist above is not a suggestion.",
	"Denied. You cannot ship a ✗. We checked. Repeatedly.",
	"Blocked. Buy the missing upgrades first — the ✗ rows, specifically.",
	"No. And the button will keep saying no until the checklist is all ✓.",
]

func _on_ship() -> void:
	if not GameManager.can_ship():
		# Refuse usefully: restate the checklist with the refusal on top of it.
		_update_ship_status()
		var status: Label = $Panel/Margin/VBox/ShipStatus
		status.text = "%s\n%s" % [_Comedy.pick("ship_denial", _DENIALS), status.text]
		status.add_theme_color_override("font_color", _GameTheme.TEXT)
		AudioManager.play_sfx("denied")
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
