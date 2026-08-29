extends Control
## Cinematic main menu — the first frame is a scene, not a panel in a void:
## a parallax neon skyline drifts behind the 3AM apartment corner (desk,
## monitor running code-rain, the vibe coder silhouetted in its glow), dust
## motes hang in the air, the overbright title pulses with a whisper of CRT
## chromatic fringing, and the neon buttons slide toward the cursor. It still
## states the premise in one breath and rotates a tip pool so nobody reads the
## same joke twice while deciding whether to press New Game.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

const CITY_SHADER := "res://assets/shaders/menu_skyline.gdshader"
const CODE_RAIN_SHADER := "res://assets/shaders/code_rain.gdshader"
const GEN_TEX_DIR := "res://assets/textures/generated/"

## Dry build notes appended to the version string. Short — it's a footnote.
const BUILD_NOTES := [
	"built at 3AM",
	"no tests were harmed",
	"ships with known issues (deliberate)",
	"one (1) hackathon",
	"compiled on hope",
	"works on our machine",
	"semver: aspirational",
	"changelog: 'stuff'",
	"reviewed by the author",
	"tabs, obviously",
]

## Moon geometry, shared by the shader parameter and the keep-clear maths so
## the two can never drift apart. Radius is a fraction of the window WIDTH.
const MOON_R := 0.042
const MOON_X := 0.815
const MOON_Y := 0.135

var _starfield_mat: ShaderMaterial
var _city_mat: ShaderMaterial
var _apartment: Control
var _drift: CPUParticles2D
var _tip_scrim: TextureRect

func _ready() -> void:
	var theme := _GameTheme.create()
	$CenterPanel.theme = theme
	$CenterPanel/VBox/Title.text = "TOKEN RUNNER"
	$CenterPanel/VBox/Subtitle.text = "Ship Before Reset"
	$CenterPanel/VBox/Version.text = "v1.1-dev — Localhost rebuild · %s" % _Comedy.pick("build_note", BUILD_NOTES)
	$CenterPanel/VBox/NewGame.text = "New Game"
	$CenterPanel/VBox/NewGame.tooltip_text = "Start a fresh run. New repo, same you."
	$CenterPanel/VBox/ContinueBtn.text = "Continue (Pretending This Is Fine)"
	$CenterPanel/VBox/ContinueBtn.tooltip_text = "Load your save and resume the run in progress."
	$CenterPanel/VBox/SettingsBtn.text = "Settings Nobody Changes"
	$CenterPanel/VBox/SettingsBtn.tooltip_text = "Volume, fullscreen and camera shake. All of them genuinely work."
	$CenterPanel/VBox/QuitBtn.text = "Quit And Touch Grass"
	$CenterPanel/VBox/QuitBtn.tooltip_text = "Exits the game. The grass has 100% uptime and needs no YAML."
	$CenterPanel/VBox/ContinueBtn.visible = SaveManager.has_save()
	$CenterPanel/VBox/NewGame.pressed.connect(_on_new_game)
	$CenterPanel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$CenterPanel/VBox/SettingsBtn.pressed.connect(_on_settings)
	$CenterPanel/VBox/QuitBtn.pressed.connect(_on_quit)
	$TipLabel.text = _Comedy.pick("menu_tip", _Comedy.MENU_TIPS)
	_build_premise()
	_build_cityscape()
	_build_apartment()
	_build_ambient_particles()
	_dress_background()
	_dress_panel()
	_dress_tagline()
	_dress_title()
	_dress_buttons()
	_start_tip_rotation()
	resized.connect(_on_root_resized)

## The premise, stated once, plainly, before anyone has pressed anything: what
## you are doing and in what order. The joke is the last clause, never the goal.
func _build_premise() -> void:
	var premise := Label.new()
	premise.name = "Premise"
	premise.text = "One night. One token quota. One Dream App to finish.\nCollect tokens → buy upgrades [B] → meet the ship requirements → Deploy before the reset."
	premise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	premise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	premise.add_theme_font_size_override("font_size", 15)
	premise.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.AMBER, 0.9))
	var vbox: VBoxContainer = $CenterPanel/VBox
	vbox.add_child(premise)
	vbox.move_child(premise, 3)  # after Version, before the button spacer

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
	# Vignette between the stars and the panel — depth on the cheap. It slots
	# UNDER the apartment corner: the radial falloff is darkest exactly in the
	# corners, and the hero scene must not sit inside it (the skyline behind
	# still gets the full depth treatment). Held at 0.58, not the old 0.85: the
	# corners are where the moon and the foreground spires now live, and at 0.85
	# the vignette ate them and handed the upper frame back to the void.
	var vig := _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.VOID, 0.58))
	add_child(vig)
	move_child(vig, _apartment.get_index() if _apartment else $CenterPanel.get_index())
	# Faint cyan aurora along the top edge, breathing slowly. Its height is a
	# fraction of the window, not the scene's fixed 400px — at 1440 that flat
	# 400 left the aurora hugging the very top instead of grading into the sky.
	var glow: ColorRect = get_node_or_null("GlowTop")
	if glow:
		glow.offset_bottom = _glow_height(get_viewport_rect().size)
		_fade_glow_top(glow)
		var gt := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		gt.tween_property(glow, "modulate:a", 0.5, 3.2)
		gt.tween_property(glow, "modulate:a", 1.0, 3.2)

## Height of the top aurora band, proportional so it grades into the same part
## of the sky at every supported resolution.
func _glow_height(vp: Vector2) -> float:
	return maxf(vp.y * 0.42, 120.0)

## GlowTop is authored as a FLAT ColorRect, so its baseline is a ruled
## horizontal line across the whole frame. Measured in the QA capture: the row
## above it reads (0,8,15) and the row below (0,3,10) — a visible edge, and the
## band now sits over a lit sky instead of a black one, where a straight line
## across the upper third is exactly the thing that says "rectangle", not
## "place". Same node, same node name, same cyan: the fill just moves into a
## vertical gradient that reaches zero before the band ends. Peak is nudged
## 0.04 -> 0.06 so the top of the aurora holds its old strength once the rest
## of it is fading.
func _fade_glow_top(glow: ColorRect) -> void:
	if glow.has_node("AuroraFade"):
		return
	var tint := glow.color
	glow.color = _GameTheme.with_alpha(tint, 0.0)
	var fade := _vertical_fade(
			_GameTheme.with_alpha(tint, 0.06), _GameTheme.with_alpha(tint, 0.042), 0.38)
	fade.name = "AuroraFade"
	glow.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## One-directional fade as a stretched 4x256 gradient: `near` at the anchored
## edge, `mid` a fraction `mid_at` along, fully transparent at the far edge.
## `from_top` false anchors it to the bottom instead. Cheap, filtered smooth by
## the TextureRect, and it never grows an edge of its own the way a flat rect
## does. Callers own the anchoring.
func _vertical_fade(near: Color, mid: Color, mid_at: float,
		from_top: bool = true) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, mid_at, 1.0])
	grad.colors = PackedColorArray([near, mid, _GameTheme.with_alpha(near, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0 if from_top else 1.0)
	tex.fill_to = Vector2(0.5, 1.0 if from_top else 0.0)
	tex.width = 4
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Parallax neon skyline between the starfield and the room — an entirely
## procedural shader wall (menu_skyline.gdshader). Four building layers with
## lit windows and rooftop beacons drift a few pixels per second under a graded
## sky carrying two cloud decks, a moon and a handful of aircraft beacons, so
## the upper half of the first frame is a place rather than a black rectangle.
## The horizon sits at 0.54 (was 0.62): the roofline crosses the panel instead
## of hiding beneath it, and the tall foreground spires reach into the top
## third. Sky pixels stay partly transparent so the starfield keeps showing
## through — most at the top, least at the horizon where the city glow drowns
## the stars. Every measure is a UV fraction, so the composition holds from
## 1280x720 to 2560x1440.
func _build_cityscape() -> void:
	if not ResourceLoader.exists(CITY_SHADER):
		return
	var city := ColorRect.new()
	city.name = "Cityscape"
	city.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = load(CITY_SHADER)
	var vp := get_viewport_rect().size
	# Seed every uniform we ever touch again (tween/resize rule, HANDOVER §4.2).
	_city_mat.set_shader_parameter("rect_width", maxf(vp.x, 1.0))
	_city_mat.set_shader_parameter("rect_aspect", _aspect_of(vp))
	_city_mat.set_shader_parameter("horizon", 0.54)
	_city_mat.set_shader_parameter("drift_speed", 1.0)
	_city_mat.set_shader_parameter("window_glow", 1.0)
	_city_mat.set_shader_parameter("scroll", Vector2.ZERO)
	_city_mat.set_shader_parameter("haze_color", _GameTheme.with_alpha(_GameTheme.VIOLET, 1.0))
	_city_mat.set_shader_parameter("cool_color", _GameTheme.with_alpha(_GameTheme.CYAN, 1.0))
	_city_mat.set_shader_parameter("warm_color", _GameTheme.with_alpha(_GameTheme.AMBER, 1.0))
	_city_mat.set_shader_parameter("beacon_color", _GameTheme.with_alpha(_GameTheme.RED, 1.0))
	# Sky dressing. The moon sits upper-right — opposite the apartment corner in
	# the lower-left, and clear of the centre panel down to a 1280-wide window.
	_city_mat.set_shader_parameter("sky_color",
			_GameTheme.with_alpha(_GameTheme.BASE.lerp(_GameTheme.VIOLET, 0.16), 1.0))
	_city_mat.set_shader_parameter("sky_amount", 1.0)
	_city_mat.set_shader_parameter("cloud_amount", 1.0)
	_city_mat.set_shader_parameter("cloud_speed", 1.0)
	_city_mat.set_shader_parameter("moon_uv", _moon_uv(vp))
	_city_mat.set_shader_parameter("moon_size", MOON_R)
	_city_mat.set_shader_parameter("moon_color",
			_GameTheme.with_alpha(_GameTheme.WHITE_HOT.lerp(_GameTheme.BLUE, 0.25), 1.0))
	_city_mat.set_shader_parameter("aircraft_amount", 1.0)
	_city_mat.set_shader_parameter("spire_amount", 1.0)
	city.material = _city_mat
	add_child(city)
	move_child(city, $Starfield.get_index() + 1)

## Viewport height/width — the skyline shader needs it to keep the moon and the
## beacon dots round on any window shape.
func _aspect_of(vp: Vector2) -> float:
	return clampf(vp.y / maxf(vp.x, 1.0), 0.2, 2.0)

## Where the moon hangs. Nominally 0.815 of the width, but on a narrow window
## the 640px-wide centre panel creeps outward in UV terms, so the moon is
## pushed right just far enough to keep a 24px gap from the panel's edge — the
## panel stays the focal point and the moon never becomes a badge on it.
func _moon_uv(vp: Vector2) -> Vector2:
	var clear_x := 0.5 + (320.0 + 24.0) / maxf(vp.x, 1.0) + MOON_R
	return Vector2(clampf(maxf(MOON_X, clear_x), MOON_X, 0.88), MOON_Y)

## The 3AM apartment, suggested rather than built: desk, monitor mid-scroll,
## the vibe coder silhouetted against the glow. Anchored to the bottom-left so
## the corner survives every resolution (scaled with the window height in
## _on_root_resized). Every texture is exists()-guarded per the manifest rule.
func _build_apartment() -> void:
	var apt := Control.new()
	apt.name = "ApartmentScene"
	apt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(apt)
	move_child(apt, $CenterPanel.get_index())
	apt.scale = Vector2.ONE * clampf(get_viewport_rect().size.y / 720.0, 1.0, 2.0)
	_apartment = apt
	# Monitor halo first: the light source everything else silhouettes against.
	var halo := _make_sprite("fx_radial_soft.png", Vector2(150, -185), 3.2, false)
	if halo:
		halo.name = "Halo"
		halo.material = _GameTheme.additive_material()
		halo.modulate = Color(0.35, 1.5, 1.35, 0.46)
		apt.add_child(halo)
		var ht := halo.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ht.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ht.tween_property(halo, "modulate:a", 0.32, 2.7)
		ht.tween_property(halo, "modulate:a", 0.46, 2.7)
	var monitor := _make_sprite("furn_monitor.png", Vector2(150, -170), 1.25)
	if monitor:
		monitor.name = "Monitor"
		monitor.modulate = Color(0.72, 0.78, 0.95)
		apt.add_child(monitor)
		# The screen runs code_rain (shader_material seeds all four uniforms).
		var rain_mat := _GameTheme.shader_material(CODE_RAIN_SHADER, {
			"tint": Color(0.16, 0.95, 0.75, 1.0),
			"columns": 10.0,
			"speed": 0.85,
			"alpha_max": 0.6,
		})
		if rain_mat:
			var rain := ColorRect.new()
			rain.name = "CodeRain"
			rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rain.color = Color(0, 0, 0, 0)
			# The screen well of furn_monitor.png (96x84) spans local -44..44 x
			# -38..16; inset 1px so the bezel's inner AO ring stays visible and
			# the glyphs never touch the chin vents below the well.
			rain.position = Vector2(-43, -37)
			rain.size = Vector2(86, 53)
			rain.material = rain_mat
			monitor.add_child(rain)
	var desk := _make_sprite("furn_desk.png", Vector2(168, -76), 1.25)
	if desk:
		desk.name = "Desk"
		desk.modulate = Color(0.5, 0.55, 0.72)
		apt.add_child(desk)
	var chair := _make_sprite("furn_chair.png", Vector2(84, -118), 1.25)
	if chair:
		chair.name = "Chair"
		chair.modulate = Color(0.28, 0.32, 0.5)
		apt.add_child(chair)
	# Rim first (drawn behind): a cyan edge so the silhouette reads as lit
	# from the screen, per the silhouette law.
	var rim := _make_sprite("player_idle.png", Vector2(108, -140), 1.25)
	if rim:
		rim.name = "PlayerRim"
		rim.material = _GameTheme.additive_material()
		rim.modulate = Color(0.3, 1.3, 1.2, 0.3)
		apt.add_child(rim)
	var player := _make_sprite("player_idle.png", Vector2(108, -138), 1.25)
	if player:
		player.name = "PlayerSil"
		player.modulate = Color(0.16, 0.2, 0.34)
		apt.add_child(player)
	# One warm accent in all that cyan: a desk LED breathing at ~0.1Hz.
	var led := _make_sprite("fx_glow_dot.png", Vector2(252, -130), 2.2, false)
	if led:
		led.name = "DeskLed"
		led.material = _GameTheme.additive_material()
		led.modulate = Color(2.0, 1.25, 0.35, 0.8)
		apt.add_child(led)
		var lt := led.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lt.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		lt.tween_property(led, "modulate:a", 0.5, 4.8)
		lt.tween_property(led, "modulate:a", 0.8, 4.8)
	# Dust caught in the monitor light (emitter 2 of 2 — far under budget).
	var motes_tex := _load_tex("fx_glow_dot.png")
	if motes_tex:
		var motes := CPUParticles2D.new()
		motes.name = "MonitorMotes"
		motes.texture = motes_tex
		motes.amount = 12
		motes.lifetime = 8.0
		motes.preprocess = 8.0
		motes.position = Vector2(150, -180)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(52, 34)
		motes.direction = Vector2(0, -1)
		motes.spread = 180.0
		motes.gravity = Vector2(0.0, -2.0)
		motes.initial_velocity_min = 1.0
		motes.initial_velocity_max = 4.0
		motes.scale_amount_min = 0.08
		motes.scale_amount_max = 0.2
		motes.color = Color(0.55, 1.0, 0.95, 0.3)
		motes.material = _GameTheme.additive_material()
		apt.add_child(motes)

## Screen-wide dust motes drifting through the neon — the room feels
## inhabited. Emitter 1 of 2; both together sit far under the bible's
## per-region particle budget.
func _build_ambient_particles() -> void:
	var tex := _load_tex("fx_glow_dot.png")
	if tex == null:
		return
	var p := CPUParticles2D.new()
	p.name = "AmbientDrift"
	p.texture = tex
	p.amount = 26
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(1.5, -3.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.35
	p.color = Color(0.62, 0.85, 1.0, 0.16)
	p.material = _GameTheme.additive_material()
	p.position = get_viewport_rect().size * 0.5
	p.emission_rect_extents = get_viewport_rect().size * 0.55
	add_child(p)
	move_child(p, $CenterPanel.get_index())
	_drift = p

## exists()-guarded texture load from the generated-asset manifest.
func _load_tex(file: String) -> Texture2D:
	var path := GEN_TEX_DIR + file
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## exists()-guarded Sprite2D factory for the backdrop set dressing. Pixel
## sprites get NEAREST filtering so they stay crisp when the corner scales.
func _make_sprite(file: String, pos: Vector2, scl: float, pixel: bool = true) -> Sprite2D:
	var tex := _load_tex(file)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2.ONE * scl
	if pixel:
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s

## One resize hook for everything that measures the window: skyline pixel width
## and aspect (round moon, round beacons), the moon's keep-clear from the panel,
## the aurora band and the tagline's ground scrim, apartment corner scale, the
## screen-wide dust volume, and stale hover-slide baselines (the VBox re-lays
## rows out after a resize).
func _on_root_resized() -> void:
	var vp := get_viewport_rect().size
	if _city_mat:
		_city_mat.set_shader_parameter("rect_width", maxf(vp.x, 1.0))
		_city_mat.set_shader_parameter("rect_aspect", _aspect_of(vp))
		_city_mat.set_shader_parameter("moon_uv", _moon_uv(vp))
	if _apartment:
		_apartment.scale = Vector2.ONE * clampf(vp.y / 720.0, 1.0, 2.0)
	var glow: ColorRect = get_node_or_null("GlowTop")
	if glow:
		glow.offset_bottom = _glow_height(vp)
	_fit_tip_scrim(vp)
	if _drift:
		_drift.position = vp * 0.5
		_drift.emission_rect_extents = vp * 0.55
	for btn: Button in [$CenterPanel/VBox/NewGame, $CenterPanel/VBox/ContinueBtn,
			$CenterPanel/VBox/SettingsBtn, $CenterPanel/VBox/QuitBtn]:
		if btn.has_meta("_slide_base_x"):
			# Snap the row home BEFORE dropping the baseline: a button mid-slide
			# (keyboard focus held through the resize) would otherwise donate its
			# displaced x as the next capture and rest 8px right forever.
			var old: Variant = btn.get_meta("_slide_tw") if btn.has_meta("_slide_tw") else null
			if old is Tween and (old as Tween).is_valid():
				(old as Tween).kill()
			var base_x: float = btn.get_meta("_slide_base_x")
			btn.position.x = base_x
			btn.remove_meta("_slide_base_x")

func _dress_panel() -> void:
	var panel: PanelContainer = $CenterPanel
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 26.0))
	_GameTheme.add_sheen(panel, Color(1, 1, 1, 0.04), 9.0)
	_GameTheme.open_panel(panel)

## The bottom tagline lands on top of lit windows now that the skyline reaches
## the frame edge, so contrast cannot come from colour alone. Two guarantees:
## the standard outline floor (a 4px near-black halo is what actually keeps a
## glyph off a bright window pane) and the brighter TEXT token, over the ground
## scrim below. It stays a footnote: 15px against the 18px buttons, well under
## the panel, and the pool's longest line still fits one row of the 900px box.
func _dress_tagline() -> void:
	var tip: Label = $TipLabel
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT, 0.94))
	_GameTheme.outline_text(tip, 4)
	_build_tip_scrim()
	tip.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(tip, "modulate:a", 1.0, _GameTheme.T_DRAMA)

## The strip under the tagline is the busiest in the frame — the near layer's
## lit windows run straight through the line. A lozenge sized to the label does
## not survive it: the tip pool runs to ~90 characters (measured 641px of glyphs
## in the QA frame), and a radial falloff wide enough to hold that has already
## spent itself to ~4% alpha by the last word, so the ends of the longest tips
## get no help at all. A ground shadow rising from the bottom edge is the one
## scrim shape with no edge of its own: it runs off three sides and dies out
## into the city on the fourth, and it covers every tip length identically at
## every resolution.
func _build_tip_scrim() -> void:
	# 0.68 at the frame edge falling to nothing a third of the way up puts ~0.5
	# under the glyph rows: enough to halve a lit window pane without turning
	# the bottom of the city off. The vignette gave up some of "edges darkest"
	# when it dropped to 0.58 for the moon; this hands that back where it helps.
	var tr := _vertical_fade(_GameTheme.with_alpha(_GameTheme.VOID, 0.68),
			_GameTheme.with_alpha(_GameTheme.VOID, 0.36), 0.5, false)
	tr.name = "TipScrim"
	add_child(tr)
	# Under the apartment corner — the hero scene keeps its own values — and
	# over the skyline, so only the city behind the line is darkened.
	move_child(tr, _apartment.get_index() if _apartment else $CenterPanel.get_index())
	tr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tip_scrim = tr
	_fit_tip_scrim(get_viewport_rect().size)

## Scrim depth: it has to clear the tagline's box (72px up from the bottom) with
## enough room left over for the gradient to reach zero well above it, so the
## darkening never announces where it started.
func _fit_tip_scrim(vp: Vector2) -> void:
	if _tip_scrim == null:
		return
	_tip_scrim.offset_top = -maxf(vp.y * 0.21, 168.0)
	_tip_scrim.offset_bottom = 0.0

## A new tip every nine seconds, never repeating until the pool is exhausted —
## the menu is where most of these get read, so it must not loop back quickly.
func _start_tip_rotation() -> void:
	var tip: Label = $TipLabel
	var t := create_tween().set_loops()
	t.tween_interval(9.0)
	t.tween_property(tip, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void:
		tip.text = _Comedy.pick("menu_tip", _Comedy.MENU_TIPS))
	t.tween_property(tip, "modulate:a", 1.0, 0.5)

func _dress_title() -> void:
	var title: Label = $CenterPanel/VBox/Title
	title.add_theme_font_override("font", _GameTheme.spaced_font(8))
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	var glow := _GameTheme.add_glow_layer(title, 2.2)
	_GameTheme.pulse(glow, 1.4, 2.3, 3.0)
	# CRT chromatic fringing: a magenta and a cyan ghost a hair either side of
	# the title, drifting a pixel in and out. Built AFTER the glow layer so the
	# duplicate above didn't clone them into itself.
	_add_chroma_ghost(title, _GameTheme.MAGENTA, -1.8, "ChromaL")
	_add_chroma_ghost(title, _GameTheme.CYAN, 1.8, "ChromaR")
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
		_attach_hover_slide(btn)
	_GameTheme.stagger_rows($CenterPanel/VBox, 0.06, 0.15)

## One additive off-tint copy of the title, slightly off-center — the pair
## reads as slow CRT fringing. Drift is ~1px over seconds; nothing strobes.
func _add_chroma_ghost(title: Label, tint: Color, dx: float, ghost_name: String) -> void:
	var ghost := Label.new()
	ghost.name = ghost_name
	ghost.text = title.text
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.add_theme_font_override("font", title.get_theme_font("font"))
	ghost.add_theme_font_size_override("font_size", title.get_theme_font_size("font_size"))
	ghost.add_theme_color_override("font_color", _GameTheme.with_alpha(tint, 0.3))
	ghost.material = _GameTheme.additive_material()
	ghost.show_behind_parent = true
	title.add_child(ghost)
	ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost.position = Vector2(dx, 0.0)
	var t := ghost.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(ghost, "position:x", dx * 0.35, 3.4)
	t.tween_property(ghost, "position:x", dx, 3.4)

## Hover/focus nudge: the row slides 8px right and back. Position is only
## borrowed between layout passes — the base is dropped in _on_root_resized
## whenever the VBox re-sorts, and re-captured on the next hover.
func _attach_hover_slide(btn: Button) -> void:
	btn.mouse_entered.connect(func() -> void: _hover_slide(btn, true))
	btn.mouse_exited.connect(func() -> void: _hover_slide(btn, false))
	btn.focus_entered.connect(func() -> void: _hover_slide(btn, true))
	btn.focus_exited.connect(func() -> void: _hover_slide(btn, false))

func _hover_slide(btn: Button, hovered: bool) -> void:
	if not is_instance_valid(btn) or not btn.is_inside_tree():
		return
	if not btn.has_meta("_slide_base_x"):
		btn.set_meta("_slide_base_x", btn.position.x)
	var base_x: float = btn.get_meta("_slide_base_x")
	var old: Variant = btn.get_meta("_slide_tw") if btn.has_meta("_slide_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := btn.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(btn, "position:x", base_x + (8.0 if hovered else 0.0), _GameTheme.T_MICRO * 1.4)
	btn.set_meta("_slide_tw", t)

func _on_new_game() -> void:
	AudioManager.play_sfx("ui_click")
	# A fresh run gets fresh jokes: clear the no-repeat bags so the death and tip
	# pools start from a full deck.
	_Comedy.reset_session()
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
