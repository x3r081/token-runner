extends PanelContainer
## World map / fast travel. Every locked region says exactly which quest opens
## it, and the region holding your current objective is called out.
##
## Round 6 removed the rainbow. Every row used to glow in its destination's
## accent — ten hues in one 640px panel, plus a chip, plus a breathing tween on
## "you are here", plus an emoji per row at a completely different pixel size
## from everything around it. LAW 8: the current region is the one ACCENT, the
## rest is TEXT_DIM, locked rows sit at 40%.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

## How far back a locked region sits. It still has to be READABLE — it is where
## the unlock condition is printed — but it is not somewhere you can go.
const LOCKED_ALPHA := 0.4

const REGION_NAMES := {
	"localhost": "Localhost",
	"dependency_district": "Dependency District",
	"stackoverflow_ruins": "Stack Overflow Ruins",
	"api_bazaar": "API Bazaar",
	"cloud_district": "Cloud District",
	"open_source_wildlands": "Open Source Wildlands",
	"corporate_enterprise": "Corporate Enterprise",
	"gpu_mines": "GPU Mines",
	"production": "Production",
	"token_vault": "Token Vault",
}

## The literal unlock condition for every region. This is load-bearing guidance:
## it is the only thing a locked row is allowed to say.
const UNLOCK_HINTS := {
	"localhost": "Where you live. It was never locked.",
	"dependency_district": "Open from the start — walk out of Localhost.",
	"stackoverflow_ruins": "Complete 'Install Node' in Dependency District.",
	"api_bazaar": "Complete 'Accepted Answer (2013)' in Stack Overflow Ruins.",
	"cloud_district": "Complete 'One More API Call' in API Bazaar.",
	"open_source_wildlands": "Complete 'We Should Move To The Cloud' in Cloud District.",
	"corporate_enterprise": "Complete 'The Dependency That Nobody Maintains' in Open Source Wildlands.",
	"gpu_mines": "Complete 'Just Add AI' in Corporate Enterprise.",
	"production": "Complete 'Mine Your Own Business' in GPU Mines.",
	"token_vault": "Complete 'Production Is Down' in Production.",
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 6.0))
	_Modal.attach_scrim(self)
	offset_left = -320.0
	offset_right = 320.0
	_Modal.place_centred(self, 640.0)
	var title: Label = $Margin/VBox/Title
	title.add_theme_font_size_override("font_size", _Modal.HEADING)
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	$Margin/VBox/CloseBtn.text = "Close"
	$Margin/VBox/CloseBtn.tooltip_text = "Closes the map. [M] does it too."
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_build_subtitle()
	_populate()
	_GameTheme.open_panel(self)
	# The region list grows as regions unlock, so the panel is sized to its
	# content instead of to a fixed rect.
	$Margin/VBox.minimum_size_changed.connect(_fit_to_content)
	_fit_to_content()
	# One more pass after the containers have sorted: autowrapped notes only know
	# their real wrapped height once they have been given their real width.
	_fit_to_content.call_deferred()
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

## Re-fits the panel to whatever the region list currently needs, clamped into
## the space the HUD is not using. Idempotent and cheap — safe to run from a
## layout signal, which is how it catches the pass where autowrapped notes learn
## their real wrapped height.
func _fit_to_content() -> void:
	if not is_inside_tree():
		return
	# Floor as well as ceiling: a measurement taken before the notes have wrapped
	# reads short, and a stub panel is a worse failure than a little dead space.
	var want: float = maxf(get_combined_minimum_size().y + 6.0, 420.0)
	# A Control never draws smaller than its minimum size, so once the list is
	# taller than the space between the HUD's two bands, setting the offsets does
	# nothing — the panel just hangs off the bottom over the ability bar. This map
	# GROWS all game, so that end state has to be handled here rather than
	# discovered in a late-game screenshot.
	var ceiling: float = _Modal.fitted_height(self, 100000.0)
	if want > ceiling and _trim_flavour_notes():
		_Modal.place_centred(self, ceiling)
		return
	var target := _Modal.fitted_height(self, want)
	if absf((offset_bottom - offset_top) - target) < 2.0:
		return
	_Modal.place_centred(self, want)

## Flavour is first out of the lifeboat. The locked-region unlock conditions are
## guidance and stay whatever happens. One-way, so it cannot oscillate against
## the resize it triggers. Returns true if anything was actually hidden.
func _trim_flavour_notes() -> bool:
	var trimmed := false
	for c in $Margin/VBox/RegionList.get_children():
		var ctrl := c as Control
		if ctrl != null and ctrl.has_meta("flavour") and ctrl.visible:
			ctrl.visible = false
			trimmed = true
	return trimmed

func _build_subtitle() -> void:
	var sub := Label.new()
	sub.name = "MapSubtitle"
	sub.text = "Fast travel is instant and free. Everything at the other end is neither."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", _Modal.SMALL)
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(sub)
	vbox.move_child(sub, 1)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/RegionList
	for c in vbox.get_children():
		c.queue_free()
	vbox.add_theme_constant_override("separation", 4)
	# Where the game currently wants you — surfaced right on the map.
	var objective: Dictionary = QuestManager.get_current_objective() if QuestManager else {}
	var target_region := String(objective.get("region", ""))
	for rid in GameManager.REGION_ORDER:
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var display: String = REGION_NAMES.get(rid, rid)
		var flag: String = ""
		if rid == target_region:
			flag = "   · objective"
		if unlocked and not current:
			# Fast-travel to any unlocked region. Buttons stay direct children of
			# RegionList (the travel test counts them there).
			var btn := Button.new()
			btn.text = "%s%s" % [display, flag]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.tooltip_text = _Comedy.region_subtitle(rid)
			_GameTheme.style_button(btn, _GameTheme.TEXT_DIM, _Modal.SMALL)
			var r: String = rid
			btn.pressed.connect(func(): _travel(r))
			vbox.add_child(btn)
		else:
			var label := Label.new()
			label.add_theme_font_size_override("font_size", _Modal.SMALL)
			if current:
				# The one accent on this screen: where you are standing.
				label.text = "%s   · you are here%s" % [display, flag]
				label.add_theme_color_override("font_color", _GameTheme.CYAN)
				vbox.add_child(label)
				_add_note(vbox, _Comedy.region_subtitle(rid), _GameTheme.TEXT_DIM, true)
			else:
				label.text = "%s   · locked" % display
				label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
				label.modulate.a = LOCKED_ALPHA
				vbox.add_child(label)
				# The unlock condition, and only the unlock condition. The taunt
				# that used to lead this line was the same joke ten times.
				var how: String = UNLOCK_HINTS.get(rid, "It opens as a quest reward.")
				_add_note(vbox, how, _GameTheme.TEXT_DIM)
	# No reveal_rows() here on purpose: locked rows carry a deliberate 40% alpha
	# (LAW 8), and a blanket "everything to 1.0" pass would erase exactly the
	# hierarchy this list is built out of.

## Small dim second line under a region row. Stays a direct child of RegionList
## so the travel-button count the map test asserts on is unaffected.
## `flavour` marks the line as cuttable if the list ever outgrows the panel.
func _add_note(vbox: VBoxContainer, text: String, col: Color, flavour := false) -> void:
	var note := Label.new()
	note.text = "      %s" % text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", _Modal.SMALL)
	note.add_theme_color_override("font_color", col)
	if not flavour:
		note.modulate.a = LOCKED_ALPHA
	if flavour:
		note.set_meta("flavour", true)
	vbox.add_child(note)

func _travel(rid: String) -> void:
	if GameManager.is_region_unlocked(rid) and rid != GameManager.current_region:
		GameManager.change_region(rid)
	queue_free()
