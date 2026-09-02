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
##
## Round 7 removed the rest of the words, and the hole they were sitting in.
## The QA frame showed a 100px block of nothing above the divider and then
## twenty-five lines of small type, which is a wall, not a shop. Now the panel
## says exactly six things, in this order:
##
##   DREAM APP                          the heading
##   Not shippable · 5 outstanding      one status line (and the receipt slot)
##   ────────────────
##   a README that says 'TODO: ...'     ONE line while there is no architecture;
##                                      the diagram appears when there is one
##   Features 0 · Stability 0 · ...     what you have built
##   [ ] Features 0/15 · ...            why you cannot ship
##   You have 70 tk · ... · +2% debt    what you can spend
##   nine upgrade rows                  one line each
##   Deploy To Production               the one primary action
##
## Everything cut from here is still in the game. The branch jokes moved to the
## row tooltips, the framing paragraphs to [H]. Nothing that carries a NUMBER
## was removed — a shop with no prices is not restraint, it is a broken shop.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

const _ArchDiagram = preload("res://scripts/ui/arch_diagram.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _subtitle: Label = $Panel/Margin/VBox/Subtitle
@onready var _ship_btn: Button = $Panel/Margin/VBox/ShipBtn

var _diagram: Control
var _arch_line: Label
var _wallet: Label
var _base_subtitle := ""

## False once the column has proved it cannot afford the diagram at all. Separate
## from "there is nothing to diagram yet", because the two want different
## fallbacks: no architecture gets a one-line placeholder, no ROOM gets silence.
var _diagram_affordable := true

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
## every upgrade/decision — plus the one line that stands in for it before there
## is anything to draw.
func _setup_diagram() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox
	var slot: int = $Panel/Margin/VBox/HSeparator.get_index() + 1
	_diagram = _ArchDiagram.new()
	vbox.add_child(_diagram)
	vbox.move_child(_diagram, slot)
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
	_diagram_affordable = (_panel.offset_bottom - _panel.offset_top) >= 700.0
	# THE 100px HOLE. With nothing purchased the diagram printed two lines of text
	# and then reserved a hundred and fifty-six pixels underneath them for boxes
	# that do not exist yet — an empty block sitting directly under the title,
	# which is the first thing the critic's eye landed on. A Control cannot draw
	# smaller than its minimum size, so the only fix is to not have the Control:
	# it is hidden until there is an architecture, and one line says so instead.
	_arch_line = Label.new()
	_arch_line.name = "ArchLine"
	_arch_line.text = "Architecture: a README that says 'TODO: everything'"
	_GameTheme.small_text(_arch_line)
	_arch_line.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vbox.add_child(_arch_line)
	vbox.move_child(_arch_line, slot + 1)
	_diagram.refresh()
	_sync_diagram()

## True once any branch has been bought — i.e. once the diagram would draw a box
## rather than an apology.
func _has_architecture() -> bool:
	for b: String in DreamAppManager.BRANCHES:
		if DreamAppManager.get_branch_tier(b) > 0:
			return true
	return false

## Exactly one of the diagram and its placeholder is ever visible, and when the
## column has run out of room, neither is.
func _sync_diagram() -> void:
	if not is_instance_valid(_diagram) or not is_instance_valid(_arch_line):
		return
	var live: bool = _diagram_affordable and _has_architecture()
	_diagram.visible = live
	_arch_line.visible = _diagram_affordable and not live

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
	_GameTheme.small_text(_wallet)
	_wallet.add_theme_color_override("font_color", _GameTheme.TEXT)
	col.add_child(_wallet)
	col.move_child(_wallet, scroll.get_index())
	_panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 18.0))
	# One ACCENT on this screen: the title and the Deploy button. Everything else
	# is TEXT or TEXT_DIM, including the nine Buy buttons — a shop where every row
	# is gold is a shop with no hierarchy.
	_title.add_theme_color_override("font_color", _GameTheme.CYAN)
	# The subtitle slot no longer carries a tagline. "holographic dev console ·
	# v0.0.1-alpha" told the player nothing they could act on; the one line
	# directly under the heading is now the ship status, and a purchase borrows it
	# for its receipt. One line, doing two jobs that both matter.
	_GameTheme.small_text(_subtitle)
	_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var totals_label: Label = $Panel/Margin/VBox/Totals
	_GameTheme.small_text(totals_label)
	totals_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var status_label: Label = $Panel/Margin/VBox/ShipStatus
	_GameTheme.small_text(status_label)
	_GameTheme.style_button(_ship_btn, _GameTheme.CYAN, _Modal.BODY)
	_GameTheme.style_button($Panel/Margin/VBox/CloseBtn, _GameTheme.TEXT_DIM, _GameTheme.SMALL)
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
		# ONE line per row. It used to be two — the offer, then a joke about the
		# offer — which is nine jokes nobody asked for stacked into the middle of a
		# price list, and half of the wall the critic counted. The joke is still
		# attached to the row, in the tooltip, where reading it is a choice
		# (LAW 10). What survives on screen is the offer and its cost in debt,
		# because those are the two numbers the decision is made on.
		var info := Label.new()
		var branch_name: String = DreamAppManager.upgrade_defs.get(branch, {}).get("display", branch)
		if next.is_empty():
			info.text = "%s: MAX — %s" % [branch_name, DreamAppManager.get_upgrade_name(branch)]
			info.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
			info.tooltip_text = _Comedy.branch_quip(branch)
		else:
			info.text = "%s [%d]  →  %s" % [branch_name, tier, next.get("name", "?")]
			info.tooltip_text = "%s\n\n%s" % [next.get("description", ""), _next_note(next, branch)]
			info.add_theme_color_override("font_color", _GameTheme.TEXT)
		info.add_theme_font_size_override("font_size", _Modal.BODY)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(info)
		if not next.is_empty():
			# The debt this tier adds, in TEXT_DIM on the same line as the offer.
			# Debt silently raises the price of everything bought afterwards, so it
			# is a price, not flavour, and it stays on screen.
			var debt := int(next.get("debt", 0))
			if debt > 0:
				var cost_note := Label.new()
				cost_note.text = "+%d debt" % debt
				_GameTheme.small_text(cost_note)
				cost_note.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
				cost_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				cost_note.tooltip_text = _Comedy.branch_quip(branch)
				h.add_child(cost_note)
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
			_GameTheme.style_button(btn, _GameTheme.TEXT_DIM, _GameTheme.SMALL)
			var b: String = branch
			btn.pressed.connect(func(): _purchase(b))
			h.add_child(btn)
		vbox.add_child(h)
	_Modal.reveal_rows(vbox)
	_update_totals()

## The debt a tier adds (real number) plus the joke about it. This used to be a
## printed second line under every row; it is now the tail of the row's tooltip,
## which is the same information in a place the player opts into.
func _next_note(next: Dictionary, branch: String) -> String:
	var debt := int(next.get("debt", 0))
	if debt > 0:
		return "+%d debt · %s" % [debt, _Comedy.branch_quip(branch)]
	return _Comedy.branch_quip(branch)

## Totals row: what you have built, in three numbers.
##
## The sentence that used to follow them — "Prices include your debt surcharge
## (+2%); every upgrade adds more" — was the panel's longest line and its least
## useful shape: a paragraph explaining a number. The number itself now rides the
## wallet line, next to the money it applies to, where it is read at the moment
## it matters. The explanation lives in [H].
func _update_totals() -> void:
	var totals := DreamAppManager.get_totals()
	$Panel/Margin/VBox/Totals.text = "Features %d · Stability %d · Security %d" % [
		totals.features, totals.stability, totals.security]
	_update_wallet()
	_sync_diagram()
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
	if not _diagram_affordable:
		return
	var col: VBoxContainer = $Panel/Margin/VBox
	# Granted height, not size.y: if the column has already overflowed, size.y IS
	# the overflow and the test would pass while the panel hangs off the bottom.
	# 24 = Margin top+bottom (12 each), 36 = the modal box's content margin.
	var budget: float = (_panel.offset_bottom - _panel.offset_top) - 24.0 - 36.0
	if col.get_combined_minimum_size().y > budget:
		_diagram_affordable = false
		_sync_diagram()

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
	var line := "You have  %s" % "  ·  ".join(parts)
	# The debt surcharge, attached to the money it inflates instead of to a
	# sentence about itself. Hidden at 0%, because "+0%" is a fact about nothing.
	var surcharge := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))
	if surcharge > 0:
		line += "   ·   prices +%d%% (debt)" % surcharge
	_wallet.text = line

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

## Comedic receipt, borrowing the status line for a few seconds. It always names
## what you bought and what it cost you in debt, then hands the slot back to the
## ship status — which by then reads one requirement lower, which is the point.
func _confirm_purchase(bought: String, debt: int) -> void:
	var line := "%s — %s" % [bought, _Comedy.purchase_quip()]
	if debt > 0:
		line = "%s (+%d debt) — %s" % [bought, debt, _Comedy.debt_quip()]
	_subtitle.text = line
	_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT)
	_subtitle.set_meta("_receipt", true)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(3.4)
	t.tween_callback(func() -> void:
		if is_instance_valid(_subtitle):
			_subtitle.remove_meta("_receipt")
			_subtitle.text = _base_subtitle
			_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM))

## The ship checklist: an explicit [x]/[ ] per requirement, so "why can't I deploy"
## is
## answered without guesswork.
##
## The framing sentence that used to sit on top of it has moved INTO the status
## line under the title, where it is the only thing that line does — "Not
## shippable · 5 requirements outstanding" says the same thing as "NOT SHIPPABLE
## — 5 requirements left. Buy the unticked rows below." in half the words, and
## those rows are directly beneath it, so the instruction was telling the player
## what they were already looking at.
##
## THE MARKS ARE ASCII. `GameTheme.ui_font()` reports has_char() == false for
## U+2713 ✓ and U+2717 ✗, so both were coming from an unchosen fallback face at
## a hinting setting nobody picked; the same hole rendered the quest log's ☐ as
## a stray horizontal stroke. [x] / [ ] is in the font and matches the bracket
## idiom the HUD already uses for keys.
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
		var mark := "[x]"
		if not ok:
			mark = "[ ]"
			missing += 1
		rows.append("  %s %s %d/%d" % [mark, String(entry[0]), int(d.current), int(d.required)])
	status.text = "\n".join(rows)
	status.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if ready:
		_base_subtitle = "Shippable · press Deploy"
	else:
		var plural := "s"
		if missing == 1:
			plural = ""
		_base_subtitle = "Not shippable · %d requirement%s outstanding" % [missing, plural]
	# A purchase receipt is currently holding the slot; it reverts on its own
	# timer, and stamping the status over it mid-tween would eat the receipt.
	if not _subtitle.has_meta("_receipt"):
		_subtitle.text = _base_subtitle
		_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# The button stays pressable when it would refuse — a dead button teaches
	# nothing; a refusal does. It no longer pulses for attention: it is the only
	# accent-coloured control in the panel, which is attention enough.
	if ready:
		_ship_btn.text = "Deploy To Production"
	else:
		_ship_btn.text = "Deploy To Production  (not yet)"

const _DENIALS := [
	"Deploy refused. The unticked rows below are not a suggestion.",
	"Denied. You cannot ship a [ ]. We checked. Repeatedly.",
	"Blocked. Buy the missing upgrades first — the unticked rows, specifically.",
	"No. And the button will keep saying no until the checklist is all [x].",
]

func _on_ship() -> void:
	if not GameManager.can_ship():
		# Refuse usefully, in the status line, with the checklist it is refusing on
		# directly underneath. The refusal used to be prepended to the checklist
		# itself, which grew the block by a line every time the player pressed the
		# button — the one place in the panel where words multiplied.
		_update_ship_status()
		_subtitle.text = _Comedy.pick("ship_denial", _DENIALS)
		_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT)
		_subtitle.set_meta("_receipt", true)
		var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(3.4)
		t.tween_callback(func() -> void:
			if is_instance_valid(_subtitle):
				_subtitle.remove_meta("_receipt")
				_subtitle.text = _base_subtitle
				_subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM))
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
