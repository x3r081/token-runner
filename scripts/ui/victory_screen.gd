extends Control

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
Quests Completed: %d
Deaths: %d
Play Time: %s""" % [
		results.features, results.stability,
		DreamAppManager.get_totals().security,
		results.technical_debt,
		results.quests_completed,
		results.deaths,
		_format_time(results.play_time),
	]
	$Panel/VBox/Flavor.text = _get_flavor(results.ranking)
	$Panel/VBox/ContinueBtn.text = "Continue in Post-Game"
	$Panel/VBox/MenuBtn.text = "Return to Main Menu"
	$Panel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$Panel/VBox/MenuBtn.pressed.connect(_on_menu)
	SaveManager.save_game()

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
