extends Control
## The title screen: a night skyline, a moon, one lit window in the foreground
## with somebody still working behind it, and a panel with four words on it.
##
## Round 6 took things away (VISUAL_BIBLE_V2 LAW 8). Gone: the parallax starfield
## shader, the procedural skyline shader with its cloud decks and aircraft
## beacons, the aurora band, the vignette, the ground scrim, two particle
## emitters, the additive monitor halo, the player rim-light, the breathing desk
## LED, the title's glow layer and its two chromatic-aberration ghosts, the panel
## sheen, the button hover-slide, the row cascade, the typewriter subtitle, the
## rotating tip, and the three-line premise (it lives in [H], where it is asked
## for). What is left is drawn here, by hand, on one 2px grid:
##
##   * three flat sky bands and a ground band — no gradient, no filter;
##   * a starfield at 8% brightness, because the top third of the frame was
##     literally #000000 and read as a rendering fault rather than as night;
##   * a moon that is a disc and one crater tone, drawn in 4px cells;
##   * two building layers, the near one carrying AT MOST 60 lit windows in
##     exactly two colours: WARM and ACCENT. Not confetti;
##   * the 3AM corner, lit by one monitor. One light source, no halo pass.
##
## The whole frame is three hues. That is the entire trick.
##
## THE QUIET RECT. Every one of those decisions is made ONCE and then clipped
## against `_quiet_rect()` — the panel plus a margin. The backdrop simply does
## not light a window or place a star there. This is the fix for the QA frame in
## which fifteen orange and cyan window panes floated on top of the menu: the
## modal body is BASE at 96% (LAW 8) and the compositor blends in linear space,
## so 4% of #FFB74A over a near-black panel is not "invisible", it is a solid
## (58,38,28) dot sitting on the word "Continue". Nudging the alpha would only
## move the threshold; not drawing behind the panel removes the class of bug.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

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

# ------------------------------------------------------------- backdrop art ----

## Every drawn pixel is a 2x2 block, snapped to the grid (LAW 1). Nothing in this
## backdrop is drawn at a half-step, so nothing shimmers on a resize.
const PX := 2.0

## LAW 4's window budget, enforced rather than hoped for. The previous skyline
## shader lit "a few per building" in green, orange and cyan and the result was
## confetti; sixty warm windows and a handful of cyan ones is a city at 3AM.
const MAX_WINDOWS := 60

## Localhost's three hues (LAW 2) and the darks between them. There is no fourth.
const SKY_HIGH := Color("#07060C")
const SKY_LOW := Color("#0E0C14")
const CITY_FAR := Color("#111019")
const CITY_NEAR := Color("#191826")
const GROUND := Color("#08070E")
const MOON_LIT := Color("#C9CEDC")
const MOON_CRATER := Color("#AAB0C2")
const WARM := Color("#FFB74A")

## Moon geometry as fractions of the frame, so the composition holds from
## 1280x720 to 2560x1440. Upper right, opposite the apartment corner, clear of
## the panel at every supported width.
const MOON_R := 0.038
const MOON_X := 0.815
const MOON_Y := 0.135

const HORIZON := 0.66

## Stars. Two tones, both at or under 8% of white — dim enough that they are
## texture rather than content (LAW 3 spends brightness on five things and a star
## is not one of them), bright enough that the sky is not a black rectangle.
## 8.0% and 6.0% of white, neutral. Not a colour choice so much as a measurement:
## the 2D buffer is linear and 8-bit, so anything under ~7.9% sRGB quantises to
## the same single code value as everything below it — two tones authored closer
## together than this would render as one tone with extra draw calls.
const MAX_STARS := 64
const STAR := Color(0.079, 0.079, 0.080)
const STAR_DIM := Color(0.058, 0.058, 0.060)

## Margin around the panel inside which the backdrop draws nothing bright.
const QUIET_PAD := 14.0

func _ready() -> void:
	# Theme on the ROOT, not just the panel: the tip line lives outside the panel
	# and has to inherit the same aliased default font as everything inside it.
	theme = _GameTheme.create()
	$CenterPanel/VBox/Title.text = "TOKEN RUNNER"
	$CenterPanel/VBox/Subtitle.text = "Ship Before Reset"
	$CenterPanel/VBox/Version.text = "v1.1-dev · %s" % _Comedy.pick("build_note", BUILD_NOTES)
	$CenterPanel/VBox/NewGame.text = "New Game"
	$CenterPanel/VBox/NewGame.tooltip_text = "Start a fresh run. New repo, same you."
	$CenterPanel/VBox/ContinueBtn.text = "Continue"
	$CenterPanel/VBox/ContinueBtn.tooltip_text = "Load your save and resume the run in progress."
	$CenterPanel/VBox/SettingsBtn.text = "Settings"
	$CenterPanel/VBox/SettingsBtn.tooltip_text = "Volume, fullscreen and camera shake. All of them genuinely work."
	$CenterPanel/VBox/QuitBtn.text = "Quit and Touch Grass"
	$CenterPanel/VBox/QuitBtn.tooltip_text = "Exits the game. The grass has 100% uptime and needs no YAML."
	$CenterPanel/VBox/ContinueBtn.visible = SaveManager.has_save()
	$CenterPanel/VBox/NewGame.pressed.connect(_on_new_game)
	$CenterPanel/VBox/ContinueBtn.pressed.connect(_on_continue)
	$CenterPanel/VBox/SettingsBtn.pressed.connect(_on_settings)
	$CenterPanel/VBox/QuitBtn.pressed.connect(_on_quit)
	_build_apartment()
	_dress_panel()
	_dress_tip()
	resized.connect(_on_root_resized)

# ------------------------------------------------------------------ backdrop ----

## The whole night sky, in one pass, behind every child of this Control.
##
## It is drawn rather than shaded on purpose: a shader that generates clouds,
## beacons, haze and window noise cannot be given a window BUDGET, and the budget
## is the entire point of LAW 4. Here the count is a variable you can read.
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 1.0 or h < 1.0:
		return
	var horizon := _snap(h * HORIZON)
	# Sky: three flat steps, darkest at the top. Steps, not a gradient — a smooth
	# vertical ramp is what made the old aurora read as a rectangle with an edge.
	draw_rect(Rect2(0.0, 0.0, w, horizon), SKY_HIGH)
	var mid := _snap(h * 0.40)
	draw_rect(Rect2(0.0, mid, w, horizon - mid), SKY_LOW)
	var low := _snap(h * 0.56)
	draw_rect(Rect2(0.0, low, w, horizon - low), SKY_LOW.lerp(WARM, 0.045))
	draw_rect(Rect2(0.0, horizon, w, h - horizon), GROUND)
	var quiet := _quiet_rect()
	_draw_stars(w, h, quiet)
	_draw_moon(Vector2(_snap(w * MOON_X), _snap(h * MOON_Y)), _snap(w * MOON_R))
	_draw_skyline(w, h, horizon, quiet)

## The panel's rect plus a margin — the region of the frame the backdrop leaves
## alone. Taken from the anchors and offsets rather than from `get_rect()`,
## because `_draw()` can run on the frame BEFORE the container has sorted its
## children and a zero-sized rect there would let a window through exactly once.
func _quiet_rect() -> Rect2:
	var p: Control = $CenterPanel
	return Rect2(
		size.x * 0.5 + p.offset_left, size.y * 0.5 + p.offset_top,
		p.offset_right - p.offset_left, p.offset_bottom - p.offset_top
	).grow(QUIET_PAD)

## A night sky instead of a black rectangle. Deterministic, budgeted, and clipped
## out of the panel — the same three rules the windows follow.
func _draw_stars(w: float, h: float, quiet: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771103
	# Stars stop well above the rooftops: the near towers reach h*0.38 up from the
	# horizon at h*0.66, so anything below h*0.30 would be a star inside a
	# building, which the skyline then paints over — wasted budget and, at the
	# edges, a star apparently stuck to a wall.
	var ceiling := h * 0.30
	# The moon owns its own patch of sky. A star touching the disc reads as a
	# stuck pixel, not as a star behind the moon.
	var moon_c := Vector2(w * MOON_X, h * MOON_Y)
	var moon_r: float = w * MOON_R + 18.0
	for _i in MAX_STARS:
		var p := Vector2(_snap(rng.randf() * w), _snap(rng.randf() * ceiling))
		if quiet.has_point(p) or p.distance_to(moon_c) < moon_r:
			continue
		draw_rect(Rect2(p.x, p.y, PX, PX), STAR if rng.randf() < 0.6 else STAR_DIM)

## A disc and one crater tone, in 4px cells. No blur, no bloom, no halo — the
## previous moon was a radial gradient, which is why it read as a smudge.
func _draw_moon(c: Vector2, r: float) -> void:
	var cell := PX * 2.0
	var n := int(ceil(r / cell))
	for gy in range(-n, n + 1):
		for gx in range(-n, n + 1):
			var p := Vector2(float(gx), float(gy)) * cell
			if p.length() > r:
				continue
			var col := MOON_LIT
			# Three hand-placed craters. Placed, not noised: x, y and radius as
			# fractions of the moon so they hold at every resolution.
			for cr: Vector3 in [
					Vector3(-0.30, -0.24, 0.26),
					Vector3(0.26, 0.12, 0.18),
					Vector3(-0.04, 0.42, 0.13)]:
				if (p - Vector2(cr.x, cr.y) * r).length() <= cr.z * r:
					col = MOON_CRATER
					break
			draw_rect(Rect2(_snap(c.x + p.x), _snap(c.y + p.y), cell, cell), col)

## Two layers. The far one is a silhouette and gets no windows at all — it exists
## so the near layer has something to stand in front of.
func _draw_skyline(w: float, h: float, horizon: float, quiet: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	var x := -40.0
	while x < w:
		var bw := _snap(rng.randf_range(56.0, 124.0))
		var bh := _snap(rng.randf_range(h * 0.09, h * 0.21))
		draw_rect(Rect2(_snap(x), horizon - bh, bw, bh), CITY_FAR)
		x += bw + _snap(rng.randf_range(4.0, 22.0))
	# Shapes first, windows second. The budget is shared out across the buildings
	# instead of being spent front to back: spending it in draw order lit the left
	# nine towers and left the right third of the frame completely dark, which
	# reads as a rendering fault rather than as a city at 3AM.
	var rects: Array[Rect2] = []
	x = -60.0
	while x < w:
		var bw := _snap(rng.randf_range(84.0, 164.0))
		var bh := _snap(rng.randf_range(h * 0.15, h * 0.38))
		var rect := Rect2(_snap(x), horizon - bh, bw, bh)
		rects.append(rect)
		draw_rect(rect, CITY_NEAR)
		x += bw + _snap(rng.randf_range(10.0, 36.0))
	var left := MAX_WINDOWS
	for i in rects.size():
		# ceil(left / remaining): self-levelling, so the last tower is never dark
		# and the total can never exceed the budget.
		var share := int(ceil(float(left) / float(rects.size() - i)))
		left -= _draw_windows(rects[i], rng, share, quiet)

## Lit windows on one building: at most `share` of them, scattered over the whole
## facade. Two colours only — WARM for most, ACCENT for the few rooms where
## somebody else is also still awake.
func _draw_windows(r: Rect2, rng: RandomNumberGenerator, share: int, quiet: Rect2) -> int:
	if share <= 0:
		return 0
	var pane := Vector2(PX * 3.0, PX * 5.0)
	var step := Vector2(PX * 9.0, PX * 13.0)
	var cols := int(floor((r.size.x - step.x * 2.0) / step.x))
	var rows := int(floor((r.size.y - step.y * 2.0) / step.y))
	if cols < 1 or rows < 1:
		return 0
	# ~14% of the facade lit, capped by this building's share of the budget.
	var want := mini(share, maxi(1, int(round(float(cols * rows) * 0.14))))
	var taken := {}
	var lit := 0
	# Bounded attempts: a repeated cell is skipped, never retried forever.
	for _try in want * 3:
		if lit >= want:
			break
		var cx := rng.randi() % cols
		var cy := rng.randi() % rows
		var key := cy * cols + cx
		if taken.has(key):
			continue
		taken[key] = true
		var p := r.position + step + Vector2(float(cx) * step.x, float(cy) * step.y)
		var col: Color = WARM if rng.randf() < 0.76 else _GameTheme.CYAN
		var pane_rect := Rect2(_snap(p.x), _snap(p.y), pane.x, pane.y)
		# Behind the panel, that room is dark. The budget is still spent, on
		# purpose: re-rolling it would push the skipped windows out to the panel's
		# edge and ring the menu in orange, which is a worse frame than a quiet
		# hole in the facade nobody can see into anyway.
		lit += 1
		if quiet.intersects(pane_rect):
			continue
		draw_rect(pane_rect, col)
	return lit

func _snap(v: float) -> float:
	return floorf(v / PX) * PX

# ----------------------------------------------------------------- apartment ----

## The 3AM corner: desk, monitor, chair, and the coder silhouetted against the
## one light in the frame. Fixed scale 2.0 on every sprite (LAW 1) — the corner
## no longer grows with the window, so its pixels are the same size as the
## skyline's at every resolution.
func _build_apartment() -> void:
	var apt := Control.new()
	apt.name = "ApartmentScene"
	apt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(apt)
	move_child(apt, $CenterPanel.get_index())
	# The one motivated light source in the frame (LAW 3): a soft pool from the
	# monitor. Normal blend at low alpha — the old additive pass at 1.5x was the
	# green blob that swallowed the lower-left quarter of the screen.
	var pool := _make_sprite("fx_radial_soft.png", Vector2(240, -272), 2.6, false)
	if pool:
		pool.name = "MonitorLight"
		pool.modulate = Color(0.55, 0.86, 0.82, 0.22)
		apt.add_child(pool)
	var monitor := _make_sprite("furn_monitor.png", Vector2(240, -272), 2.0)
	if monitor:
		monitor.name = "Monitor"
		monitor.modulate = Color(0.74, 0.80, 0.94)
		apt.add_child(monitor)
		# The screen itself, lit. A flat rect in the bezel's well (local
		# -43..43 x -37..16 in furn_monitor.png), not a shader.
		var screen := ColorRect.new()
		screen.name = "Screen"
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.30)
		screen.position = Vector2(-43, -37)
		screen.size = Vector2(86, 53)
		monitor.add_child(screen)
	var desk := _make_sprite("furn_desk.png", Vector2(268, -122), 2.0)
	if desk:
		desk.name = "Desk"
		desk.modulate = Color(0.46, 0.50, 0.66)
		apt.add_child(desk)
	var chair := _make_sprite("furn_chair.png", Vector2(134, -188), 2.0)
	if chair:
		chair.name = "Chair"
		chair.modulate = Color(0.26, 0.29, 0.44)
		apt.add_child(chair)
	var player := _make_sprite("player_idle.png", Vector2(172, -220), 2.0)
	if player:
		player.name = "PlayerSil"
		player.modulate = Color(0.20, 0.24, 0.38)
		apt.add_child(player)

## exists()-guarded texture load from the generated-asset manifest.
func _load_tex(file: String) -> Texture2D:
	var path := GEN_TEX_DIR + file
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## exists()-guarded Sprite2D factory for the backdrop set dressing. Pixel
## sprites get NEAREST filtering so the 2x grid stays a 2x grid.
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

# ---------------------------------------------------------------------- panel ----

func _dress_panel() -> void:
	var panel: PanelContainer = $CenterPanel
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 28.0))
	var title: Label = $CenterPanel/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	var subtitle: Label = $CenterPanel/VBox/Subtitle
	subtitle.add_theme_color_override("font_color", _GameTheme.TEXT)
	var version: Label = $CenterPanel/VBox/Version
	version.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	for l: Label in [subtitle, version]:
		_small(l)
	# One ACCENT per screen: the title, and the button you came here to press.
	_GameTheme.style_button($CenterPanel/VBox/NewGame, _GameTheme.CYAN, _Modal.BODY)
	for btn: Button in [$CenterPanel/VBox/ContinueBtn, $CenterPanel/VBox/SettingsBtn,
			$CenterPanel/VBox/QuitBtn]:
		_GameTheme.style_button(btn, _GameTheme.TEXT_DIM, _Modal.BODY)
	_GameTheme.open_panel(panel)

## One tip, chosen once, in TEXT_DIM. It used to rotate every nine seconds with a
## crossfade, which meant the title screen never stopped moving.
func _dress_tip() -> void:
	var tip: Label = $TipLabel
	tip.text = _Comedy.pick("menu_tip", _Comedy.MENU_TIPS)
	tip.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_small(tip)

## The SMALL tier, as a SIZE and nothing else.
##
## Every label on this screen inherits the theme's default font — the aliased,
## hinted one `_ready` installs on the root — and none of them may override it.
## The tip line did: it went through a helper that swapped in a separately
## rasterised, ANTI-ALIASED face, so the captured menu frame carried a title
## drawn in 4 tones and a tip drawn in 89. Two typographic systems on one
## screen, and the smooth one is the "generated" tell LAW 1 exists to remove.
##
## A size override alone is safe now: the theme's font gained the autohinter
## this round, which is what the antialiasing had been compensating for — the
## HUD's own 16px legend renders "[E] interact · [T] model · [H] help" aliased
## and clean in every captured region frame.
func _small(l: Label) -> void:
	l.add_theme_font_size_override("font_size", _GameTheme.SMALL)

func _on_root_resized() -> void:
	queue_redraw()

# --------------------------------------------------------------------- actions ----

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
