extends Control
## The ship screen is the payoff, so the roast is the reward. It reads back the
## architecture you actually shipped, the corners you actually cut, and the
## postmortem that has, statistically, already been written.
##
## Round 6: black background, one GOLD title, the report, one button. Gone are
## the gold vignette, the gold-bordered panel with its gold glow, the moving gold
## sheen, the title's glow layer and pulse, the staggered rows — and a third of
## the report, which used to run to twenty lines of bullet points.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

var _hint_label: Label

func _ready() -> void:
	get_tree().paused = true
	var results := GameManager.get_ship_results()
	var rid := int(results.get("architecture_ridiculousness", 0))
	$Panel/VBox/Title.text = "YOU SHIPPED IT"
	$Panel/VBox/Ranking.text = str(results.ranking)
	$Panel/VBox/Score.text = "Score %d · %s" % [results.score, _Comedy.ridiculousness_quip(rid)]
	$Panel/VBox/Details.text = "Features %d · Stability %d · Security %d · Debt %d · Ridiculousness %d\nQuests %d · Deaths %d · Time %s" % [
		results.features, results.stability,
		DreamAppManager.get_totals().security,
		results.technical_debt,
		rid,
		results.quests_completed,
		results.deaths,
		_format_time(results.play_time),
	]
	$Panel/VBox/Flavor.text = _build_report(results)
	$Panel/VBox/ContinueBtn.text = "Continue in Post-Game"
	$Panel/VBox/ContinueBtn.tooltip_text = "The app is live. Its bugs are now everyone's problem, including yours."
	$Panel/VBox/MenuBtn.text = "Main Menu"
	$Panel/VBox/MenuBtn.tooltip_text = "Roll credits. Nobody stays for the credits."
	_build_hint_row()
	$Panel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$Panel/VBox/MenuBtn.pressed.connect(_on_menu)
	_dress()
	SaveManager.save_game()

## Plain statement of what "post-game" means, so the two buttons aren't a coin flip.
func _build_hint_row() -> void:
	_hint_label = Label.new()
	_hint_label.name = "PostGameHint"
	_hint_label.text = "Post-game keeps the world open. Your score is already recorded."
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	var vbox: VBoxContainer = $Panel/VBox
	vbox.add_child(_hint_label)
	vbox.move_child(_hint_label, 5)

# ------------------------------------------------------------- the report ----
func _build_report(results: Dictionary) -> String:
	var roast: Array = GameManager.get_ship_roast()
	# Three bullets, not six: the report is a punchline, not a changelog.
	var shown: Array = roast.slice(0, mini(3, roast.size()))
	var parts: Array[String] = []
	parts.append(_get_flavor(results.ranking))
	parts.append("")
	parts.append("AS SHIPPED   %s" % _architecture_line())
	parts.append("CORNERS CUT   %s" % _corners_line(results))
	parts.append("")
	parts.append("  • %s" % "\n  • ".join(shown))
	parts.append("")
	parts.append("THE POSTMORTEM")
	for line: String in _postmortem():
		parts.append("  %s" % line)
	return "\n".join(parts)

## What the app actually is, in the words its own architecture diagram would use.
func _architecture_line() -> String:
	var f: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var bits: Array[String] = []
	match f.get("structure", ""):
		"monolith": bits.append("a monolith")
		"microservices": bits.append("47 microservices")
		_: bits.append("an unspecified shape")
	match f.get("database", ""):
		"sql": bits.append("SQL")
		"nosql": bits.append("NoSQL")
		_: bits.append("a database nobody chose")
	match f.get("testing", ""):
		"tests": bits.append("actual tests")
		"later": bits.append("tests scheduled for 'later'")
		_: bits.append("an unexamined test strategy")
	match f.get("security", ""):
		"secure": bits.append("security done properly")
		"velocity": bits.append("security 'patched later'")
		_: bits.append("security by omission")
	match f.get("hosting", ""):
		"cloud": bits.append("living in someone else's cloud")
		"local": bits.append("living on a Raspberry Pi")
		_: bits.append("hosted wherever it landed")
	return " · ".join(bits) + "."

## The corners are computed, not invented — every entry is a real gap in the run.
func _corners_line(results: Dictionary) -> String:
	var cut: Array[String] = []
	if DreamAppManager.get_branch_tier("security") == 0:
		cut.append("no security work at all")
	if DreamAppManager.get_branch_tier("observability") == 0:
		cut.append("zero observability")
	if DreamAppManager.get_branch_tier("database") == 0:
		cut.append("the database is exactly as you found it")
	if float(results.get("technical_debt", 0)) >= 60.0:
		cut.append("%d technical debt shipped straight to production" % int(results.technical_debt))
	if int(results.get("stability", 0)) < 12:
		cut.append("stability %d, which is a number and not a promise" % int(results.stability))
	if not GameManager.get_flag("backups"):
		cut.append("no backups, on purpose, repeatedly")
	if cut.is_empty():
		return "none visible. Deeply, deeply suspicious."
	return "%d — %s." % [cut.size(), ", ".join(cut)]

## Incident language, applied in advance. Every line is a real postmortem sentence
## with the euphemism left in and the truth put in brackets.
func _postmortem() -> Array[String]:
	var f: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var pool: Array[String] = []
	if f.get("testing") == "later":
		pool.append("\"We lacked automated coverage in the affected path.\"  (There was no unaffected path.)")
	if f.get("security") == "velocity":
		pool.append("\"Credentials were logged in plaintext during a debugging effort.\"  The effort is ongoing.")
	if f.get("database") == "nosql":
		pool.append("\"The data was present. It was simply shaped differently than expected.\"")
	if f.get("structure") == "microservices":
		pool.append("\"The outage was limited to a single service.\"  It was the one all the others call.")
	if f.get("hosting") == "cloud":
		pool.append("\"Costs scaled linearly with an unforeseen event.\"  The event was Tuesday.")
	if DreamAppManager.get_branch_tier("observability") == 0:
		pool.append("\"Time to detection: four hours. Detection method: a customer, publicly.\"")
	if ResourceManager.get_value("technical_debt") >= 60.0:
		pool.append("\"A contributing factor was known technical debt.\"  It was all of them.")
	if GameManager.death_count >= 5:
		pool.append("\"On-call experienced elevated load.\"  On-call was you. %d times." % GameManager.death_count)
	if pool.is_empty():
		pool.append("\"No customer impact was observed.\"  Nobody was looking, but still.")
	var out: Array[String] = []
	for i in mini(2, pool.size()):
		out.append(pool[i])
	out.append("Action items: 3.  Completed: 0.  Reopened next quarter: 3.")
	return out

## One GOLD title on black. You shipped; you get the currency colour, once.
func _dress() -> void:
	var bg: ColorRect = $BG
	bg.modulate.a = 1.0
	var panel: PanelContainer = $Panel
	# The report grew; give it room rather than making the container fight for it.
	panel.offset_left = -460.0
	panel.offset_right = 460.0
	panel.offset_top = -360.0
	panel.offset_bottom = 360.0
	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.GOLD, 30.0))
	var title: Label = $Panel/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.GOLD)
	$Panel/VBox/Ranking.add_theme_color_override("font_color", _GameTheme.TEXT)
	$Panel/VBox/Score.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	$Panel/VBox/Details.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var flavor: Label = $Panel/VBox/Flavor
	flavor.add_theme_color_override("font_color", _GameTheme.TEXT)
	if is_instance_valid(_hint_label):
		_hint_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_GameTheme.style_button($Panel/VBox/ContinueBtn, _GameTheme.GOLD, _Modal.BODY)
	_GameTheme.style_button($Panel/VBox/MenuBtn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_GameTheme.open_panel(panel)

func _format_time(seconds: float) -> String:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	return "%d:%02d" % [m, s]

func _get_flavor(ranking: String) -> String:
	match ranking:
		"Actually Production Ready":
			return "Against all odds, it works. Your therapist is confused and quietly proud."
		"Series A Ready":
			return "Investors are interested. Users are not. Everyone has agreed this is fine."
		"Technically A SaaS":
			return "It has a login and a monthly price. Legally, that is a SaaS."
		"VC Demo":
			return "It works perfectly in the demo. Please do not click anything else."
		"Works On My Machine":
			return "The classic. A timeless tradition. Reproducible nowhere."
		"One Customer, 47 Microservices":
			return "One user. Forty-seven services. Each with its own dashboard and opinions."
		"Enterprise Architecture Astronaut":
			return "You can see the codebase from space. Nobody can navigate it from inside."
		"$84,000 Inference Bill":
			return "You solved a €3 problem. Impressively. Repeatedly. Per request."
		_:
			return "It's shipped. Which is more than most startups manage before the money runs out."

func _on_continue() -> void:
	get_tree().paused = false
	queue_free()

func _on_menu() -> void:
	get_tree().paused = false
	GameManager.return_to_menu()
