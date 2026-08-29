extends Control
## Cinematic main menu: drifting starfield, overbright pulsing title, typewriter
## subtitle, neon buttons. The game's first impression — it dresses accordingly.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

var _starfield_mat: ShaderMaterial

func _ready() -> void:
	var theme := _GameTheme.create()
	$CenterPanel.theme = theme
	$CenterPanel/VBox/Title.text = "TOKEN RUNNER"
	$CenterPanel/VBox/Subtitle.text = "Ship Before Reset"
	$CenterPanel/VBox/Version.text = "v1.1-dev — Localhost rebuild"
	$CenterPanel/VBox/NewGame.text = "New Game"
	$CenterPanel/VBox/ContinueBtn.text = "Continue Pretending This Is Fine"
	$CenterPanel/VBox/SettingsBtn.text = "Settings Nobody Changes"
	$CenterPanel/VBox/QuitBtn.text = "Quit And Touch Grass"
	$CenterPanel/VBox/ContinueBtn.visible = SaveManager.has_save()
	$CenterPanel/VBox/NewGame.pressed.connect(_on_new_game)
	$CenterPanel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$CenterPanel/VBox/SettingsBtn.pressed.connect(_on_settings)
	$CenterPanel/VBox/QuitBtn.pressed.connect(_on_quit)
	$TipLabel.text = GameManager.get_loading_tip()
	_dress_background()
	_dress_panel()
	_dress_title()
	_dress_buttons()

## The void outside the IDE: parallax stars with a barely-perceptible drift.
func _dress_background() -> void:
	var sf: ColorRect = get_node_or_null("Starfield")
	if sf and ResourceLoader.exists(_GameTheme.STARFIELD_SHADER):
		_starfield_mat = ShaderMaterial.new()
		_starfield_mat.shader = load(_GameTheme.STARFIELD_SHADER)
		_starfield_mat.set_shader_parameter("base_color", _GameTheme.with_alpha(_GameTheme.VOID, 1.0))
		_starfield_mat.set_shader_parameter("accent_color", Color(0.25, 0.55, 0.95, 1.0))
		_starfield_mat.set_shader_parameter("density", 1.1)
		# The uniform must be explicitly set before a Tween can address it.
		_starfield_mat.set_shader_parameter("scroll", Vector2.ZERO)
		sf.material = _starfield_mat
		# Slow camera-less drift; ping-pong so the loop seam never shows.
		var t := create_tween().set_loops()
		t.tween_property(_starfield_mat, "shader_parameter/scroll", Vector2(2400.0, 1100.0), 150.0)
		t.tween_property(_starfield_mat, "shader_parameter/scroll", Vector2.ZERO, 150.0)
	# Vignette between the stars and the panel — depth on the cheap.
	var vig := _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.VOID, 0.85))
	add_child(vig)
	move_child(vig, $CenterPanel.get_index())
	# Faint cyan aurora along the top edge, breathing slowly.
	var glow: ColorRect = get_node_or_null("GlowTop")
	if glow:
		var gt := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		gt.tween_property(glow, "modulate:a", 0.5, 3.2)
		gt.tween_property(glow, "modulate:a", 1.0, 3.2)

func _dress_panel() -> void:
	var panel: PanelContainer = $CenterPanel
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 26.0))
	_GameTheme.add_sheen(panel, Color(1, 1, 1, 0.04), 9.0)
	_GameTheme.open_panel(panel)
	var tip: Label = $TipLabel
	tip.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	tip.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(tip, "modulate:a", 1.0, _GameTheme.T_DRAMA)

func _dress_title() -> void:
	var title: Label = $CenterPanel/VBox/Title
	title.add_theme_font_override("font", _GameTheme.spaced_font(8))
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	var glow := _GameTheme.add_glow_layer(title, 2.2)
	_GameTheme.pulse(glow, 1.4, 2.3, 3.0)
	var subtitle: Label = $CenterPanel/VBox/Subtitle
	subtitle.add_theme_color_override("font_color", _GameTheme.hot_of(_GameTheme.CYAN))
	subtitle.add_theme_font_override("font", _GameTheme.spaced_font(4))
	subtitle.visible_characters = 0
	var t := create_tween()
	t.tween_interval(0.45)
	t.tween_property(subtitle, "visible_characters", subtitle.text.length(), 0.7)
	var version: Label = $CenterPanel/VBox/Version
	version.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)

func _dress_buttons() -> void:
	for btn: Button in [$CenterPanel/VBox/NewGame, $CenterPanel/VBox/ContinueBtn,
			$CenterPanel/VBox/SettingsBtn, $CenterPanel/VBox/QuitBtn]:
		_GameTheme.style_button(btn, _GameTheme.CYAN, 18)
	_GameTheme.stagger_rows($CenterPanel/VBox, 0.06, 0.15)

func _on_new_game() -> void:
	AudioManager.play_sfx("ui_click")
	GameManager.start_new_game()

func _on_continue() -> void:
	AudioManager.play_sfx("ui_click")
	GameManager.continue_game()

func _on_settings() -> void:
	AudioManager.play_sfx("ui_click")
	var s := preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(s)

func _on_quit() -> void:
	get_tree().quit()
