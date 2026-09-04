extends Node
## Safe audio management — silent by default until explicitly enabled.
##
## Round 4 runtime (see docs/AUDIO_BIBLE.md, "Runtime contract"):
## - Generated WAVs (music_*/ambient_*/sfx_*) load exists()-guarded into
##   _file_streams; the synthesized beeps in _streams remain as fallback so the
##   game sounds OK at every intermediate state of the asset round.
## - Music runs on two players with an equal-power crossfade (~1.2s).
## - A third quiet ambience layer follows the region family, signal-driven.
## - SFX get ±6% pitch jitter, a per-name anti-machine-gun cooldown, and a
##   footstep round-robin fed by polling the player group's velocity here —
##   no new call sites in files this manager does not own.
## - Music ducks -6 dB while dialogue is active.
## All tweens survive get_tree().paused (PROCESS_MODE_ALWAYS +
## TWEEN_PAUSE_PROCESS) so a popup can never freeze a fade at full volume.

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX := 12

const MUSIC_CROSSFADE := 1.2
const AMBIENCE_CROSSFADE := 1.5
const AMBIENT_LEVEL := 0.32
const DUCK_LINEAR := 0.501  # -6 dB
const SFX_COOLDOWN_MS := 70
const FOOTSTEP_COOLDOWN_MS := 140
const FOOTSTEP_INTERVAL := 0.26
## "The body is moving", as velocity SQUARED, in each world's own units.
##
## 2D velocity is MAP PIXELS per second and 900 is (30 px/s)². The 3D world runs
## the same coordinate law at 1 unit per 64 px tile (Map3D.PX), so the identical
## physical speed is a number 64x smaller and its square 4096x smaller — compare
## a CharacterBody3D against 900 and the player has to sprint at 30 units/s
## (1920 px/s) before a single footstep plays.
const FOOTSTEP_MOVE_SQ_2D := 900.0
const FOOTSTEP_MOVE_SQ_3D := 900.0 / (64.0 * 64.0)
## How long an externally-driven footstep (see `play_footstep`) suppresses the
## velocity poll. Comfortably longer than a stride at any speed, short enough
## that a player who drops back to the 2D world mid-session gets its poll back.
const EXTERNAL_FOOTSTEP_HOLD_MS := 1200

## Conservative defaults — silent > startling.
var master_vol: float = 0.6
var music_vol: float = 0.25
var sfx_vol: float = 0.35

## Startup safety gates — no auto audio until validated.
var music_enabled: bool = false
var sfx_enabled: bool = true
var startup_audio_validated: bool = false

## Synthesized fallbacks. The audio test scans these for near-full-scale
## samples, so file-loaded streams live in _file_streams instead.
var _streams: Dictionary = {}
var _file_streams: Dictionary = {}
var _bus_ready := false

## Music crossfade state. music_player always aliases the ACTIVE player so the
## frozen public property keeps meaning what it always meant.
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _gain_a := 0.0
var _gain_b := 0.0
var _active_is_a := true
var _music_xfade_from := 0.0
var _current_track := ""
var _pending_music := ""
var _music_tween: Tween
var _stop_from_a := 0.0
var _stop_from_b := 0.0

## Dialogue ducking (linear multiplier on the music bus volume).
var _duck_gain := 1.0
var _duck_tween: Tween

## Ambience layer (two players so region hops crossfade instead of popping).
var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _amb_gain_a := 0.0
var _amb_gain_b := 0.0
var _amb_active_is_a := true
var _amb_xfade_from := 0.0
var _current_ambience := ""
var _amb_tween: Tween

## SFX polish state.
var _last_sfx_ms: Dictionary = {}
var _footstep_idx := 0
var _footstep_accum := 0.0
## When something outside this manager last played a footstep. Starts far enough
## in the past that the very first poll is never suppressed.
var _footstep_extern_ms := -EXTERNAL_FOOTSTEP_HOLD_MS * 10
var _player_ref: Node = null
var _watchdog_accum := 0.0

## Generated file → stream-name map. Legacy validated WAVs stay as fallback
## below the new set (other checkouts still reference them).
const _MUSIC_FILES := {
	"menu_music": "music_menu",
	"explore_music": "music_explore",
	"combat_music": "music_combat",
	"boss_music": "music_boss",
	"victory_music": "music_victory",
}

const _AMBIENCE_FILES := {
	"ambient_interior": "ambient_interior",
	"ambient_industrial": "ambient_industrial",
	"ambient_outdoor": "ambient_outdoor",
	"ambient_ethereal": "ambient_ethereal",
}

const _SFX_NAMES: Array[String] = [
	"token_collect", "quest_complete", "upgrade", "damage", "coffee",
	"ui_click", "ui_hover", "ability", "enemy_death",
	"footstep_0", "footstep_1", "footstep_2", "footstep_3",
	"dash", "portal_enter", "dialogue_blip", "choice_select",
	"projectile_shoot", "enemy_hit", "player_death", "heal", "purchase",
	"denied", "achievement", "deploy_success", "boss_spawn", "pickup_rare",
	"menu_open", "menu_close", "typing",
]

## Region → ambience family, verbatim from AUDIO_BIBLE.md.
const REGION_AMBIENCE := {
	"localhost": "interior",
	"gpu_mines": "industrial",
	"dependency_district": "industrial",
	"production": "industrial",
	"token_vault": "industrial",
	"open_source_wildlands": "outdoor",
	"stackoverflow_ruins": "outdoor",
	"api_bazaar": "outdoor",
	"cloud_district": "ethereal",
	"corporate_enterprise": "ethereal",
}

## Per-family loudness trims (linear) so utility sounds sit under the mix.
const _SFX_GAIN := {
	"footstep": 0.5,
	"typing": 0.6,
	"ui_hover": 0.7,
	"dialogue_blip": 0.7,
}

func _ready() -> void:
	# Music/ambience must keep playing (and fades keep fading) under pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	music_player = _music_a
	_amb_a = _make_player("Ambience")
	_amb_b = _make_player("Ambience")
	for i in MAX_SFX:
		sfx_players.append(_make_player("SFX"))
	_generate_procedural_audio()
	_load_file_streams()
	# Later autoloads (DialogueManager, AchievementManager…) do not exist yet;
	# connect once the whole autoload list is up.
	call_deferred("_connect_manager_signals")

func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	return p

func _setup_buses() -> void:
	if _bus_ready:
		return
	var idx := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus(idx + 1)
		AudioServer.set_bus_name(idx + 1, "Music")
		AudioServer.set_bus_send(idx + 1, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		var sfx_idx := AudioServer.get_bus_count()
		AudioServer.add_bus(sfx_idx)
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")
	if AudioServer.get_bus_index("Ambience") == -1:
		var amb_idx := AudioServer.get_bus_count()
		AudioServer.add_bus(amb_idx)
		AudioServer.set_bus_name(amb_idx, "Ambience")
		AudioServer.set_bus_send(amb_idx, "Master")
	_ensure_master_limiter()
	_bus_ready = true

## Guarantee a hard output ceiling so nothing can ever blast the player, no
## matter how many SFX stack or what a future stream contains.
func _ensure_master_limiter() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	for e in AudioServer.get_bus_effect_count(master_idx):
		if AudioServer.get_bus_effect(master_idx, e) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -3.0
	AudioServer.add_bus_effect(master_idx, limiter)

func _connect_manager_signals() -> void:
	# Arities below match the declarations EXACTLY (HANDOVER gotcha 3 — a
	# mismatched handler silently never runs).
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if not gm.region_changed.is_connected(_on_region_changed):
			gm.region_changed.connect(_on_region_changed)  # (region_id: String)
		if not gm.game_started.is_connected(_on_game_started):
			gm.game_started.connect(_on_game_started)  # ()
		if not gm.game_won.is_connected(_on_game_won):
			gm.game_won.connect(_on_game_won)  # (results: Dictionary)
		if not gm.player_died.is_connected(_on_player_died):
			gm.player_died.connect(_on_player_died)  # (message: String)
		if not gm.game_paused.is_connected(_on_game_paused):
			gm.game_paused.connect(_on_game_paused)  # (paused: bool)
	var qm := get_node_or_null("/root/QuestManager")
	if qm and not qm.quest_completed.is_connected(_on_quest_completed):
		qm.quest_completed.connect(_on_quest_completed)  # (quest_id, rewards)
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		if not dm.dialogue_started.is_connected(_on_dialogue_started):
			dm.dialogue_started.connect(_on_dialogue_started)  # (npc_id: String)
		if not dm.dialogue_ended.is_connected(_on_dialogue_ended):
			dm.dialogue_ended.connect(_on_dialogue_ended)  # (npc_id: String)
	var am := get_node_or_null("/root/AchievementManager")
	if am and not am.achievement_unlocked.is_connected(_on_achievement_unlocked):
		am.achievement_unlocked.connect(_on_achievement_unlocked)  # (id, name, description)
	var em := get_node_or_null("/root/EventManager")
	if em:
		if not em.event_triggered.is_connected(_on_event_triggered):
			em.event_triggered.connect(_on_event_triggered)  # (event_id, description)
		if not em.event_resolved.is_connected(_on_event_resolved):
			em.event_resolved.connect(_on_event_resolved)  # (event_id, choice)

func enable_music() -> void:
	music_enabled = true
	startup_audio_validated = true
	_apply_volumes()
	if _pending_music != "" and _current_track == "":
		var pending := _pending_music
		_pending_music = ""
		play_music(pending, 1.5)

func enable_sfx() -> void:
	sfx_enabled = true
	_apply_volumes()

func play_sfx(name: String) -> void:
	if not sfx_enabled:
		return
	var stream := _resolve_stream(name)
	if stream == null:
		return
	# Anti-machine-gun: per-name cooldown; the footstep round-robin shares one
	# key so cycling names cannot dodge it.
	var key := "footstep" if name.begins_with("footstep") else name
	var cooldown := FOOTSTEP_COOLDOWN_MS if key == "footstep" else SFX_COOLDOWN_MS
	var now := Time.get_ticks_msec()
	if now - int(_last_sfx_ms.get(key, -100000)) < cooldown:
		return
	_last_sfx_ms[key] = now
	var gain := float(_SFX_GAIN.get(key, 1.0))
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = randf_range(0.94, 1.06)
			p.volume_db = _to_db(sfx_vol * master_vol * gain)
			p.play()
			return

## Round-robin footstep. Public so an animation-frame hook can call it — which
## the 3D player does (3D_BIBLE §4), since a rigged walk cycle knows when a foot
## actually lands and this manager's velocity poll only knows that a body is
## moving. An external call therefore ALSO tells the poll to stand down for
## EXTERNAL_FOOTSTEP_HOLD_MS, so the two cadences can never lay steps over each
## other. Nothing in the 2D game calls this from outside `_poll_footsteps`, which
## goes through `_step()` instead — so 2D is untouched.
func play_footstep() -> void:
	_footstep_extern_ms = Time.get_ticks_msec()
	_step()

## The round-robin itself, with no "someone else is driving this" side effect.
func _step() -> void:
	play_sfx("footstep_%d" % _footstep_idx)
	_footstep_idx = (_footstep_idx + 1) % 4

func play_music(name: String, fade: float = MUSIC_CROSSFADE) -> void:
	if not music_enabled:
		# Remember what should be playing so enable_music() can resume it.
		_pending_music = name
		return
	var stream := _resolve_stream(name)
	if stream == null:
		return
	if _current_track == name and music_player.playing:
		return
	_current_track = name
	var incoming := _music_b if _active_is_a else _music_a
	var outgoing := _music_a if _active_is_a else _music_b
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_active_is_a = not _active_is_a
	music_player = incoming
	_music_xfade_from = _gain_b if _active_is_a else _gain_a
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_method(_set_music_xfade, 0.0, 1.0, maxf(fade, 0.05))
	_music_tween.tween_callback(_finish_music_xfade.bind(outgoing))

## Equal-power crossfade step: incoming rides sin, outgoing rides cos scaled
## by whatever level it had when the swap started.
func _set_music_xfade(t: float) -> void:
	var g_in := sin(t * PI * 0.5)
	var g_out := _music_xfade_from * cos(t * PI * 0.5)
	if _active_is_a:
		_gain_a = g_in
		_gain_b = g_out
	else:
		_gain_b = g_in
		_gain_a = g_out
	_update_music_volumes()

func _finish_music_xfade(outgoing: AudioStreamPlayer) -> void:
	if is_instance_valid(outgoing) and outgoing != music_player:
		outgoing.stop()

func stop_music(fade: float = 0.8) -> void:
	_current_track = ""
	_pending_music = ""
	if _music_tween:
		_music_tween.kill()
	_stop_from_a = _gain_a
	_stop_from_b = _gain_b
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_method(_set_stop_fade, 1.0, 0.0, maxf(fade, 0.05))
	_music_tween.tween_callback(_halt_music_players)
	# The settings toggle disables music_enabled right before calling this —
	# re-derive ambience volumes so the ambience layer mutes with it.
	_update_ambience_volumes()

func _set_stop_fade(s: float) -> void:
	_gain_a = _stop_from_a * s
	_gain_b = _stop_from_b * s
	_update_music_volumes()

func _halt_music_players() -> void:
	_gain_a = 0.0
	_gain_b = 0.0
	if _music_a:
		_music_a.stop()
	if _music_b:
		_music_b.stop()

func set_volumes(master: float, music: float, sfx: float) -> void:
	master_vol = clampf(master, 0.0, 1.0)
	music_vol = clampf(music, 0.0, 1.0)
	sfx_vol = clampf(sfx, 0.0, 1.0)
	_apply_volumes()

func _apply_volumes() -> void:
	_update_music_volumes()
	_update_ambience_volumes()
	var sfx_db := _to_db(sfx_vol * master_vol) if sfx_enabled else -80.0
	for p in sfx_players:
		if not p.playing:
			p.volume_db = sfx_db

func _update_music_volumes() -> void:
	if _music_a == null or _music_b == null:
		return
	var base := music_vol * master_vol * _duck_gain if music_enabled else 0.0
	_music_a.volume_db = _to_db(base * _gain_a)
	_music_b.volume_db = _to_db(base * _gain_b)

func _update_ambience_volumes() -> void:
	if _amb_a == null or _amb_b == null:
		return
	var base := AMBIENT_LEVEL * master_vol if music_enabled else 0.0
	_amb_a.volume_db = _to_db(base * _amb_gain_a)
	_amb_b.volume_db = _to_db(base * _amb_gain_b)

func _to_db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))

# --- Ambience layer -----------------------------------------------------------

func _ambience_family_for(region_id: String) -> String:
	return str(REGION_AMBIENCE.get(region_id, "outdoor"))

func _set_ambience(family: String) -> void:
	if not music_enabled or _amb_a == null:
		return
	var stream := _resolve_stream("ambient_%s" % family)
	if stream == null:
		return
	if _current_ambience == family and (_amb_a.playing or _amb_b.playing):
		return
	_current_ambience = family
	var incoming := _amb_b if _amb_active_is_a else _amb_a
	var outgoing := _amb_a if _amb_active_is_a else _amb_b
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_amb_active_is_a = not _amb_active_is_a
	_amb_xfade_from = _amb_gain_b if _amb_active_is_a else _amb_gain_a
	if _amb_tween:
		_amb_tween.kill()
	_amb_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_amb_tween.tween_method(_set_ambience_xfade, 0.0, 1.0, AMBIENCE_CROSSFADE)
	_amb_tween.tween_callback(_finish_ambience_xfade.bind(outgoing))

func _set_ambience_xfade(t: float) -> void:
	var g_in := sin(t * PI * 0.5)
	var g_out := _amb_xfade_from * cos(t * PI * 0.5)
	if _amb_active_is_a:
		_amb_gain_a = g_in
		_amb_gain_b = g_out
	else:
		_amb_gain_b = g_in
		_amb_gain_a = g_out
	_update_ambience_volumes()

func _finish_ambience_xfade(outgoing: AudioStreamPlayer) -> void:
	var active := _amb_a if _amb_active_is_a else _amb_b
	if is_instance_valid(outgoing) and outgoing != active:
		outgoing.stop()

# --- Dialogue ducking ---------------------------------------------------------

func _tween_duck(target: float) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_duck_tween.tween_method(_set_duck, _duck_gain, target, 0.3)

func _set_duck(v: float) -> void:
	_duck_gain = v
	_update_music_volumes()

# --- Signal handlers (arity-matched to the declarations) ----------------------

func _on_region_changed(region_id: String) -> void:
	play_sfx("portal_enter")
	_set_ambience(_ambience_family_for(region_id))

func _on_game_started() -> void:
	_footstep_idx = 0
	_footstep_accum = 0.0
	_footstep_extern_ms = -EXTERNAL_FOOTSTEP_HOLD_MS * 10
	_set_ambience(_ambience_family_for(GameManager.current_region))

func _on_game_won(_results: Dictionary) -> void:
	play_sfx("deploy_success")
	play_music("victory_music")

func _on_player_died(_message: String) -> void:
	play_sfx("player_death")

func _on_game_paused(paused: bool) -> void:
	play_sfx("menu_open" if paused else "menu_close")

func _on_quest_completed(_quest_id: String, _rewards: Dictionary) -> void:
	play_sfx("quest_complete")

func _on_dialogue_started(_npc_id: String) -> void:
	play_sfx("dialogue_blip")
	_tween_duck(DUCK_LINEAR)

func _on_dialogue_ended(_npc_id: String) -> void:
	_tween_duck(1.0)

func _on_achievement_unlocked(_id: String, _name: String, _description: String) -> void:
	play_sfx("achievement")

func _on_event_triggered(_event_id: String, _description: String) -> void:
	play_sfx("denied")

func _on_event_resolved(_event_id: String, _choice: int) -> void:
	play_sfx("choice_select")

# --- Per-frame: footstep poll + music/ambience watchdog -----------------------

func _process(delta: float) -> void:
	if not _bus_ready:
		return
	_poll_footsteps(delta)
	_watchdog_accum += delta
	if _watchdog_accum >= 0.5:
		_watchdog_accum = 0.0
		_music_watchdog()

## Footsteps come from watching the player group's velocity — no call sites in
## player.gd needed. Cadence lives here; play_sfx's cooldown is only the guard.
##
## The player in group "player" is a CharacterBody2D in the 2D world and a
## CharacterBody3D in the 3D one (3D_BIBLE §4); `velocity.length_squared()` reads
## the same on both, only the units differ (see FOOTSTEP_MOVE_SQ_*). The old
## single `as CharacterBody2D` cast returned null for the 3D body and this whole
## poll silently returned — a game with no footsteps and nothing logged.
func _poll_footsteps(delta: float) -> void:
	if get_tree().paused or GameManager.state != GameManager.GameState.PLAYING:
		_footstep_accum = 0.0
		return
	# Someone with a real walk cycle is driving the cadence; don't double up.
	if Time.get_ticks_msec() - _footstep_extern_ms < EXTERNAL_FOOTSTEP_HOLD_MS:
		_footstep_accum = FOOTSTEP_INTERVAL * 0.7
		return
	if not (is_instance_valid(_player_ref) and _player_ref.is_inside_tree()):
		_player_ref = get_tree().get_first_node_in_group("player")
		if _player_ref == null:
			return
	var body2 := _player_ref as CharacterBody2D
	var body3 := _player_ref as CharacterBody3D
	var moving := false
	if body2 != null:
		moving = body2.velocity.length_squared() > FOOTSTEP_MOVE_SQ_2D
	elif body3 != null:
		moving = body3.velocity.length_squared() > FOOTSTEP_MOVE_SQ_3D
	else:
		return
	if moving:
		_footstep_accum += delta
		if _footstep_accum >= FOOTSTEP_INTERVAL:
			_footstep_accum = 0.0
			# `_step()`, not `play_footstep()`: the public entry point marks the
			# cadence as externally driven, and this poll IS the cadence.
			_step()
	else:
		# Pre-load so the first step lands right as movement starts.
		_footstep_accum = FOOTSTEP_INTERVAL * 0.7

## No state_changed signal exists on GameManager, so the few transitions that
## have no signal (Continue into a run, back-to-menu) are inferred here at 2 Hz.
## Never fights opening_sequence's intentional stop_music(): that clears
## _current_track, and an empty track is left alone while PLAYING.
func _music_watchdog() -> void:
	if not music_enabled:
		return
	# Safety net: never stay ducked once dialogue is over (a missed
	# dialogue_ended would otherwise mute the mix forever).
	if _duck_gain < 0.999 and not DialogueManager.is_active:
		if _duck_tween == null or not _duck_tween.is_running():
			_tween_duck(1.0)
	match GameManager.state:
		GameManager.GameState.MENU:
			if _current_track != "menu_music":
				play_music("menu_music", 1.5)
			_set_ambience("interior")
		GameManager.GameState.PLAYING:
			if _current_track == "menu_music" or _current_track == "victory_music":
				play_music("explore_music")
			_set_ambience(_ambience_family_for(GameManager.current_region))

# --- Stream tables ------------------------------------------------------------

## Generated file first, synthesized fallback second, silence never errors.
func _resolve_stream(name: String) -> AudioStream:
	if _file_streams.has(name):
		return _file_streams[name]
	if _streams.has(name):
		return _streams[name]
	return null

func _generate_procedural_audio() -> void:
	_streams["token_collect"] = _make_tone(880.0, 0.08, 0.12)
	_streams["quest_complete"] = _make_chord([523.25, 659.25, 783.99], 0.4, 0.1)
	_streams["upgrade"] = _make_chord([392.0, 493.88, 587.33], 0.5, 0.1)
	_streams["damage"] = _make_noise_burst(0.12, 0.15)
	_streams["coffee"] = _make_tone(220.0, 0.2, 0.08)
	_streams["ui_click"] = _make_tone(1200.0, 0.04, 0.06)
	_streams["ui_hover"] = _make_tone(600.0, 0.03, 0.04)
	_streams["ability"] = _make_tone(440.0, 0.12, 0.1)
	_streams["enemy_death"] = _make_chord([200.0, 150.0], 0.3, 0.1)
	_streams["explore_music"] = _make_ambient_loop(90.0, 4.0)
	_streams["combat_music"] = _make_ambient_loop(120.0, 3.0)
	_streams["menu_music"] = _make_ambient_loop(60.0, 6.0)
	_streams["boss_music"] = _make_ambient_loop(130.0, 3.0)
	_streams["victory_music"] = _make_ambient_loop(100.0, 4.0)
	_streams["ambient_interior"] = _make_ambient_loop(55.0, 6.0)
	_streams["ambient_industrial"] = _make_ambient_loop(40.0, 5.0)
	_streams["ambient_outdoor"] = _make_ambient_loop(70.0, 6.0)
	_streams["ambient_ethereal"] = _make_ambient_loop(85.0, 7.0)
	for i in 4:
		_streams["footstep_%d" % i] = _make_noise_burst(0.05, 0.05 + 0.01 * (i % 2))
	_streams["dash"] = _make_noise_burst(0.15, 0.1)
	_streams["portal_enter"] = _make_chord([300.0, 450.0, 600.0], 0.5, 0.1)
	_streams["dialogue_blip"] = _make_tone(950.0, 0.03, 0.05)
	_streams["choice_select"] = _make_tone(700.0, 0.05, 0.06)
	_streams["projectile_shoot"] = _make_tone(320.0, 0.08, 0.08)
	_streams["enemy_hit"] = _make_noise_burst(0.08, 0.12)
	_streams["player_death"] = _make_slide(220.0, 80.0, 0.7, 0.12)
	_streams["heal"] = _make_chord([523.25, 659.25], 0.3, 0.08)
	_streams["purchase"] = _make_tone(1046.5, 0.07, 0.08)
	_streams["denied"] = _make_tone(110.0, 0.2, 0.1)
	_streams["achievement"] = _make_chord([659.25, 783.99, 987.77], 0.5, 0.1)
	_streams["deploy_success"] = _make_chord([523.25, 659.25, 783.99, 1046.5], 0.8, 0.1)
	_streams["boss_spawn"] = _make_slide(160.0, 60.0, 0.8, 0.12)
	_streams["pickup_rare"] = _make_chord([880.0, 1108.73], 0.3, 0.1)
	_streams["menu_open"] = _make_tone(500.0, 0.06, 0.05)
	_streams["menu_close"] = _make_tone(400.0, 0.06, 0.05)
	_streams["typing"] = _make_tone(1400.0, 0.02, 0.04)

func _load_file_streams() -> void:
	# Legacy validated WAVs first so they act as fallback…
	_load_file("res://assets/audio/menu_ambient.wav", "menu_music", true)
	_load_file("res://assets/audio/ambient_localhost.wav", "explore_music", true)
	# …then the round-4 generated set overrides them where present.
	for key: String in _MUSIC_FILES:
		_load_file("res://assets/audio/%s.wav" % _MUSIC_FILES[key], key, true)
	for key: String in _AMBIENCE_FILES:
		_load_file("res://assets/audio/%s.wav" % _AMBIENCE_FILES[key], key, true)
	for n: String in _SFX_NAMES:
		_load_file("res://assets/audio/sfx_%s.wav" % n, n, false)

func _load_file(path: String, stream_name: String, loop: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV:
		if loop:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			# Runtime loop_mode alone loops nothing if the importer left
			# loop_end at 0 — point it at the last PCM frame.
			if stream.loop_end <= 0:
				var bytes_per_frame := 1
				if stream.format == AudioStreamWAV.FORMAT_16_BITS:
					bytes_per_frame *= 2
				if stream.stereo:
					bytes_per_frame *= 2
				stream.loop_begin = 0
				stream.loop_end = int(float(stream.data.size()) / float(bytes_per_frame))
		else:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_file_streams[stream_name] = stream

# --- Synthesized fallbacks (8-bit, deliberately far below full scale) ---------

func _encode_sample(sample: float) -> int:
	return int(clamp((sample * 0.5 + 0.5) * 255.0, 0.0, 255.0))

func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / float(count)
		var sample := sin(TAU * freq * t) * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

func _make_chord(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / float(count)
		var sample := 0.0
		for f in freqs:
			sample += sin(TAU * float(f) * t)
		sample = sample / freqs.size() * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

func _make_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	for i in count:
		var env := 1.0 - float(i) / float(count)
		var sample := rng.randf_range(-1.0, 1.0) * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

## Descending (or rising) portamento — the sad-trombone-shaped "womp".
func _make_slide(freq_from: float, freq_to: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var f := lerpf(freq_from, freq_to, t)
		phase += TAU * f / float(sample_rate)
		var env := 1.0 - t
		data[i] = _encode_sample(sin(phase) * env * volume)
	return _wav_from_data(data, sample_rate)

func _make_ambient_loop(base_freq: float, duration: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var fade := sin(PI * float(i) / float(count - 1))
		var sample := (
			sin(TAU * base_freq * t) * 0.2
			+ sin(TAU * base_freq * 1.5 * t) * 0.08
			+ sin(TAU * base_freq * 0.5 * t) * 0.1
		) * 0.08 * fade
		data[i] = _encode_sample(sample)
	var stream := _wav_from_data(data, sample_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

func _wav_from_data(data: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
