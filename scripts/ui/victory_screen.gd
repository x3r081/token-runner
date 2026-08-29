extends Control

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	get_tree().paused = true
	var results := GameManager.get_ship_results()
	$Panel/VBox/Title.text = "YOU SHIPPED IT"
	$Panel/VBox/Ranking.text = "Final Ranking: %s" % results.ranking
	$Panel/VBox/Score.text = "Score: %d" % results.score
	$Panel/VBox/Details.text = """Features: %d
Stability: %d
Security: %d
Technical Debt: %d
Architecture Ridiculousness: %d
Quests Completed: %d
Deaths: %d
Play Time: %s""" % [
		results.features, results.stability,
		DreamAppManager.get_totals().security,
		results.technical_debt,
		results.get("architecture_ridiculousness", 0),
		results.quests_completed,
		results.deaths,
		_format_time(results.play_time),
	]
	var roast: Array = GameManager.get_ship_roast()
	$Panel/VBox/Flavor.text = "%s\n\nTHE ROAST:\n• %s" % [_get_flavor(results.ranking), "\n• ".join(roast)]
	$Panel/VBox/ContinueBtn.text = "Continue in Post-Game"
	$Panel/VBox/MenuBtn.text = "Return to Main Menu"
	$Panel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$Panel/VBox/MenuBtn.pressed.connect(_on_menu)
	_dress()
	SaveManager.save_game()

## GOLD everything: you shipped, you get the currency color.
func _dress() -> void:
	var bg: ColorRect = $BG
	bg.color = Color(0.03, 0.025, 0.01, 0.97)
	bg.modulate.a = 0.0
	var bt := bg.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	bt.tween_property(bg, "modulate:a", 1.0, _GameTheme.T_DRAMA)
	var vig := _GameTheme.make_vignette(_GameTheme.with_alpha(Color(0.2, 0.13, 0.0), 0.9))
	add_child(vig)
	move_child(vig, $Panel.get_index())
	var panel: PanelContainer = $Panel
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.GOLD, 30.0))
	_GameTheme.add_sheen(panel, _GameTheme.with_alpha(_GameTheme.GOLD, 0.07), 5.0)
	var title: Label = $Panel/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.GOLD)
	title.add_theme_font_override("font", _GameTheme.spaced_font(7))
	title.add_theme_font_size_override("font_size", 40)
	var glow := _GameTheme.add_glow_layer(title, 2.4)
	_GameTheme.pulse(glow, 1.5, 2.4, 2.6)
	$Panel/VBox/Ranking.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.GOLD))
	$Panel/VBox/Score.add_theme_color_override("font_color", _GameTheme.TEXT)
	$Panel/VBox/Details.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	$Panel/VBox/Flavor.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.style_button($Panel/VBox/ContinueBtn, _GameTheme.GOLD, 16)
	_GameTheme.style_button($Panel/VBox/MenuBtn, _GameTheme.GOLD, 14)
	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows($Panel/VBox)

func _format_time(seconds: float) -> String:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	return "%d:%02d" % [m, s]

func _get_flavor(ranking: String) -> String:
	match ranking:
		"Actually Production Ready":
			return "Against all odds, it works. Your therapist is confused."
		"Series A Ready":
			return "Investors are interested. Users are not."
		"VC Demo":
			return "It works perfectly in the demo. Please don't click anything else."
		"Works On My Machine":
			return "The classic. A timeless tradition."
		"Enterprise Architecture Astronaut":
			return "You can see the codebase from space. Nobody can navigate it."
		"$84,000 Inference Bill":
			return "You solved a $3 problem. Impressively."
		_:
			return "It's shipped. That's more than most startups."

func _on_continue() -> void:
	get_tree().paused = false
	queue_free()

func _on_menu() -> void:
	get_tree().paused = false
	GameManager.return_to_menu()
