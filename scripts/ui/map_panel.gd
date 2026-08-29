extends PanelContainer
## World map / fast travel. Every region gets a one-line description of what it
## actually is, every locked region says exactly which quest opens it (the taunt
## rides along, it does not replace the hint), and the region holding your
## current objective is called out.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

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

## Region accents from the bible, so each row glows like its destination.
const REGION_ACCENTS := {
	"localhost": Color("#FFB74A"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}

## The literal unlock condition for every region. This is load-bearing guidance:
## the joke lives in the taunt next to it, never in here.
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
	# The map takes over the screen, so it gets the full modal treatment: a dim
	# scrim behind it and a near-opaque body. At the old 0.92 the bricks, the rug
	# and the COUCH / PIZZA ARCHAEOLOGY world captions read straight through the
	# panel, and the green portal outside it stayed the brightest thing on screen
	# — the modal was losing the contrast hierarchy to the world it suppresses.
	add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 4.0))
	_Modal.attach_scrim(self)
	# Two lines per region needs more room than the original 500x560 rect.
	offset_left = -320.0
	offset_right = 320.0
	_Modal.place_centred(self, 640.0)
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	$Margin/VBox/CloseBtn.text = "Close Map"
	$Margin/VBox/CloseBtn.tooltip_text = "Closes the map. [M] does it too."
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_build_subtitle()
	_populate()
	_GameTheme.open_panel(self)
	# The region list grows as regions unlock, so the panel is sized to its
	# content instead of to a fixed rect: a fixed rect left a dead 190px band
	# above "Close Map" early on and would clip the list once all ten are open.
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
	# GROWS all game (ten regions x two lines by the end), so that end state has to
	# be handled here rather than discovered in a late-game screenshot.
	var ceiling: float = _Modal.fitted_height(self, 100000.0)
	if want > ceiling and _trim_flavour_notes():
		# Park at the ceiling right now so the top edge is correct even for the
		# one frame before the trim lands; hiding rows changes the VBox minimum,
		# which re-enters this through minimum_size_changed with the smaller
		# measurement and settles the final height.
		_Modal.place_centred(self, ceiling)
		return
	var target := _Modal.fitted_height(self, want)
	if absf((offset_bottom - offset_top) - target) < 2.0:
		return
	_Modal.place_centred(self, want)

## Flavour is first out of the lifeboat. The one-line region descriptions are
## colour; the locked-region unlock conditions underneath the locked rows are
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
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(sub)
	vbox.move_child(sub, 1)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/RegionList
	for c in vbox.get_children():
		c.queue_free()
	# Where the game currently wants you — surfaced right on the map.
	var objective: Dictionary = QuestManager.get_current_objective() if QuestManager else {}
	var target_region := String(objective.get("region", ""))
	for rid in GameManager.REGION_ORDER:
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var display: String = REGION_NAMES.get(rid, rid)
		var accent: Color = REGION_ACCENTS.get(rid, _GameTheme.CYAN)
		var flag: String = ""
		if rid == target_region:
			flag = "   ◀ your objective is here"
		if unlocked and not current:
			# Fast-travel to any unlocked region. Buttons stay direct children of
			# RegionList (the travel test counts them there).
			var btn := Button.new()
			btn.text = "▸ Travel to %s%s" % [display, flag]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.tooltip_text = _Comedy.region_subtitle(rid)
			_GameTheme.style_button(btn, accent, 15)
			var r: String = rid
			btn.pressed.connect(func(): _travel(r))
			vbox.add_child(btn)
			_add_note(vbox, _Comedy.region_subtitle(rid), _GameTheme.TEXT_DIM, true)
		else:
			var label := Label.new()
			var prefix := "📍 " if current else "🔒 "
			label.text = "%s%s%s%s" % [prefix, display, "  (you are here)" if current else "  (locked)", flag]
			if current:
				label.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
				label.add_theme_stylebox_override("normal", _GameTheme.chip_box(accent))
				label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			else:
				# A locked region still has to be READABLE — it is where the
				# unlock condition is printed. 0.55 alpha made the bottom of the
				# list look like it had been switched off. Full strength here and
				# 0.85 on the note below keeps the region NAME the louder of the
				# two, which is the whole reading order of the row.
				label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
			vbox.add_child(label)
			if current:
				_add_note(vbox, _Comedy.region_subtitle(rid), _GameTheme.TEXT_DIM, true)
				# The "you are here" beacon breathes. (Tween AFTER add_child —
				# tweens refuse to exist outside the tree, like the rest of us.)
				var t := label.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				# .from() is load-bearing: the row reveal at the end of _populate()
				# drives the same property and zeroes it first, so an unpinned
				# breath would capture 0 as its start value and leave "you are
				# here" — the one row that says where you are — crawling up from
				# invisible for two seconds.
				t.tween_property(label, "modulate:a", 0.75, 0.9).from(1.0)
				t.tween_property(label, "modulate:a", 1.0, 0.9).from(0.75)
			else:
				# Taunt first (short), then the literal unlock condition.
				var taunt: String = _Comedy.pick("locked_taunt", _Comedy.LOCKED_TAUNTS)
				var how: String = UNLOCK_HINTS.get(rid, "Keep going; it opens eventually.")
				# The unlock condition is load-bearing guidance; it does not get to
				# be a whisper just because the row above it is locked.
				_add_note(vbox, "%s  %s" % [taunt, how], _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.85))
	# Twenty rows at a fixed 0.04s step meant the bottom half of the map was still
	# invisible most of a second after opening, which read as a fading list over an
	# empty panel. Bounded cascade: everything is up in ~0.3s, all at full alpha.
	_Modal.reveal_rows(vbox)

## Small dim second line under a region row. Stays a direct child of RegionList
## so the travel-button count the map test asserts on is unaffected.
## `flavour` marks the line as cuttable if the list ever outgrows the panel — see
## _trim_flavour_notes(). Unmarked notes carry guidance and are never cut.
func _add_note(vbox: VBoxContainer, text: String, col: Color, flavour := false) -> void:
	var note := Label.new()
	note.text = "      %s" % text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", col)
	if flavour:
		note.set_meta("flavour", true)
	vbox.add_child(note)

func _travel(rid: String) -> void:
	if GameManager.is_region_unlocked(rid) and rid != GameManager.current_region:
		GameManager.change_region(rid)
	queue_free()
