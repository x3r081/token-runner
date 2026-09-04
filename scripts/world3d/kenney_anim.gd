class_name KenneyAnim
extends RefCounted
## One driver for every Kenney rigged GLB (3D_BIBLE.md §6). All the character
## packs share a 32-clip set; this finds the AnimationPlayer, marks the
## locomotion clips as loops, and exposes play(name, blend, speed).

const LOOPING := ["static", "idle", "walk", "sprint", "crouch", "sit", "drive",
	"holding-right", "holding-left", "holding-both", "run", "eat", "dance",
	"wheelchair-sit"]

var player: AnimationPlayer
var current: String = ""

static func attach(root: Node) -> KenneyAnim:
	var k := KenneyAnim.new()
	if root == null:
		return k
	k.player = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if k.player:
		for n in k.player.get_animation_list():
			var a := k.player.get_animation(n)
			if a and n in LOOPING:
				a.loop_mode = Animation.LOOP_LINEAR
	return k

func has(anim: String) -> bool:
	return player != null and player.has_animation(anim)

## Plays `anim` with a crossfade; no-op if already playing it (so callers can
## drive this every frame). Falls back through `alts` when the clip is absent.
func play(anim: String, blend: float = 0.15, speed: float = 1.0, alts: Array = []) -> void:
	if player == null:
		return
	var target := anim
	if not player.has_animation(target):
		target = ""
		for a in alts:
			if player.has_animation(str(a)):
				target = str(a)
				break
		if target == "":
			return
	if current == target and player.is_playing():
		player.speed_scale = speed
		return
	current = target
	player.speed_scale = speed
	player.play(target, blend)

func stop() -> void:
	if player:
		player.stop()
	current = ""
