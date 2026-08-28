extends RefCounted
class_name LocalhostBuilder
## Hand-composed 3AM coder apartment. A deliberately designed, zoned interior —
## battlestation on a rug, server corner, kitchen with only energy drinks, an
## unslept-in bed, a node_modules trash heap, a deprecated plant — so the space
## reads instantly as "this person has destroyed their life shipping an app,"
## not as a stamped tile field.

const GEN := "res://assets/textures/generated/"
const TILE := 64
const ROOM_W := 25   # tiles -> 1600 px
const ROOM_H := 16   # tiles -> 1024 px
const WALL_LAYER := 32

static func build(parent: Node2D) -> Dictionary:
	parent.y_sort_enabled = true
	var size := Vector2(ROOM_W * TILE, ROOM_H * TILE)
	var spawn := Vector2(720, 640)
	_build_floor(parent)
	_build_rug(parent)
	_build_walls(parent)
	_build_battlestation(parent)
	_build_gpu_rig(parent)
	_build_server_corner(parent)
	_build_kitchen(parent)
	_build_bedroom(parent)
	_build_clutter(parent)
	_build_lighting(parent)
	_build_signs(parent)
	_populate_gameplay(parent, spawn)
	return {"spawn": spawn, "size": size}

# ------------------------------------------------------------- helpers ------

static func _tex(name: String) -> Texture2D:
	var path := GEN + name + ".png"
	return load(path) if ResourceLoader.exists(path) else null

static func _put(parent: Node2D, tex_name: String, pos: Vector2, z: int, scale: float = 1.0, mod: Color = Color.WHITE) -> Sprite2D:
	var t := _tex(tex_name)
	if not t:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.position = pos
	s.z_index = z
	s.scale = Vector2(scale, scale)
	s.modulate = mod
	parent.add_child(s)
	return s

## Furniture depth: z tracks the sprite's base Y so it sorts against the player
## (which sets z_index = int(global_position.y)). Objects lower on screen draw
## in front, giving real top-down occlusion.
static func _depth(pos_y: float, half_h: float) -> int:
	return int(pos_y + half_h)

# -------------------------------------------------------------- floor -------

static func _build_floor(parent: Node2D) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for gx in ROOM_W:
		for gy in ROOM_H:
			var v := (gx * 7 + gy * 13) % 3
			# Per-tile brightness jitter + occasional grime breaks the grid so
			# tiling never reads as a stamped pattern.
			var j := rng.randf_range(-0.06, 0.05)
			var mod := Color(1.0 + j, 1.0 + j, 1.0 + j * 0.8)
			if rng.randf() < 0.06:
				mod = mod.darkened(0.18)  # coffee stain / grime
			_put(floor, "int_floor_%d" % v, Vector2(gx * TILE + TILE / 2, gy * TILE + TILE / 2), -100, 1.0, mod)

static func _build_rug(parent: Node2D) -> void:
	_put(parent, "int_rug", Vector2(560, 600), -90)

# -------------------------------------------------------------- walls -------

static func _build_walls(parent: Node2D) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var right := ROOM_W * TILE
	var bottom := ROOM_H * TILE
	# Top wall band (behind everything), with a window and a door cut in.
	for gx in ROOM_W:
		var x := gx * TILE + TILE / 2
		_put(walls, "int_wall", Vector2(x, 16), -60)
		_add_collider(walls, Vector2(x, 24), Vector2(TILE, 56))
	# Side + bottom borders (thin dark strips + colliders)
	for gy in ROOM_H:
		var y := gy * TILE + TILE / 2
		_put(walls, "int_wall_side", Vector2(20, y), -58, 1.0, Color(0.8, 0.8, 0.9))
		_put(walls, "int_wall_side", Vector2(right - 20, y), -58, 1.0, Color(0.7, 0.7, 0.8))
		_add_collider(walls, Vector2(6, y), Vector2(20, TILE))
		_add_collider(walls, Vector2(right - 6, y), Vector2(20, TILE))
	for gx in ROOM_W:
		var x2 := gx * TILE + TILE / 2
		_add_collider(walls, Vector2(x2, bottom - 6), Vector2(TILE, 20))
	# Window (night city) over the desk, and an apartment door.
	_put(walls, "int_window", Vector2(560, 40), -55)
	_put(walls, "furn_door", Vector2(1360, 46), -55)
	# Whiteboard of doom on the wall
	_put(walls, "furn_whiteboard", Vector2(950, 60), -50)

static func _add_collider(parent: Node2D, pos: Vector2, sz: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = WALL_LAYER
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	shape.shape = rect
	shape.position = pos
	wall.add_child(shape)
	parent.add_child(wall)

# --------------------------------------------------------- battlestation ----

static func _build_battlestation(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Battlestation"
	parent.add_child(z)
	# Desk against the window wall
	var desk_y := 340.0
	_put(z, "furn_desk", Vector2(520, desk_y), _depth(desk_y, 48))
	# Three comedy monitors on the desk
	_add_monitor(z, Vector2(430, 300), Color(0.15, 0.85, 0.95), "TOKEN BALANCE\n>>> 70", Color(0.2, 0.95, 0.9))
	_add_monitor(z, Vector2(540, 296), Color(0.95, 0.65, 0.2), "AI SUBSCRIPTIONS\nactive: 8", Color(1.0, 0.7, 0.3))
	_add_monitor(z, Vector2(650, 300), Color(0.95, 0.35, 0.35), "SAVINGS FROM AI\n-€713 / mo", Color(1.0, 0.45, 0.45))
	# Gaming chair, slightly askew
	_put(z, "furn_chair", Vector2(560, 470), _depth(470, 44), 1.0, Color(0.9, 0.9, 1.0))

static func _add_monitor(parent: Node2D, pos: Vector2, screen_col: Color, text: String, text_col: Color) -> void:
	var mz := _depth(pos.y, 42)
	_put(parent, "furn_monitor", pos, mz)
	# Bright emissive screen
	var screen := ColorRect.new()
	screen.size = Vector2(80, 48)
	screen.position = pos - Vector2(40, 30)
	screen.color = screen_col.darkened(0.15)
	screen.z_index = mz + 1
	parent.add_child(screen)
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos - Vector2(36, 26)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", text_col)
	lbl.z_index = mz + 2
	parent.add_child(lbl)
	# Screen glow light
	var light := PointLight2D.new()
	light.texture = _radial()
	light.energy = 0.7
	light.color = screen_col
	light.texture_scale = 1.6
	light.position = pos - Vector2(0, 10)
	parent.add_child(light)

# ------------------------------------------------------------ gpu rig -------

static func _build_gpu_rig(parent: Node2D) -> void:
	# A second workstation on the right balances the composition and fills the
	# room: a jury-rigged GPU mining/inference rig made of stacked crates.
	var z := Node2D.new()
	z.name = "GpuRig"
	parent.add_child(z)
	var desk_y := 360.0
	_put(z, "furn_desk", Vector2(1120, desk_y), _depth(desk_y, 48), 0.9)
	_add_monitor(z, Vector2(1060, 318), Color(0.95, 0.35, 0.25), "GPU TEMP\n94\u00b0C  \ud83d\udd25", Color(1.0, 0.5, 0.35))
	_add_monitor(z, Vector2(1170, 320), Color(0.4, 0.9, 0.5), "npm audit\n847 vulns\n0 fixed", Color(0.5, 1.0, 0.6))
	# stacked GPU crates
	_put(z, "furn_boxes", Vector2(1200, 470), _depth(470, 52), 0.8, Color(0.7, 0.85, 1.0))
	_put(z, "furn_chair", Vector2(1110, 470), _depth(470, 44), 1.0, Color(0.85, 0.85, 1.0))

# --------------------------------------------------------- server corner ----

static func _build_server_corner(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "ServerCorner"
	parent.add_child(z)
	_put(z, "furn_server", Vector2(1470, 200), _depth(200, 84))
	_put(z, "furn_server", Vector2(1380, 220), _depth(220, 84), 1.0, Color(0.9, 0.9, 0.95))
	# Cooling glow
	var light := PointLight2D.new()
	light.texture = _radial()
	light.energy = 0.5
	light.color = Color(0.3, 0.9, 0.5)
	light.texture_scale = 3.0
	light.position = Vector2(1420, 240)
	z.add_child(light)

# ------------------------------------------------------------- kitchen ------

static func _build_kitchen(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Kitchen"
	parent.add_child(z)
	_put(z, "furn_fridge", Vector2(120, 210), _depth(210, 66))
	_put(z, "furn_coffee", Vector2(230, 230), _depth(230, 46))
	# empty energy-drink cans on the floor
	for i in 5:
		var can := ColorRect.new()
		can.size = Vector2(10, 16)
		can.position = Vector2(180 + i * 22, 300 + (i % 2) * 14)
		can.color = [Color(0.2, 0.85, 0.35), Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.95)][i % 3]
		can.z_index = _depth(can.position.y, 8)
		z.add_child(can)

# ------------------------------------------------------------- bedroom ------

static func _build_bedroom(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Bedroom"
	parent.add_child(z)
	_put(z, "furn_bed", Vector2(1320, 840), _depth(840, 54))
	_put(z, "furn_shelf", Vector2(1500, 640), _depth(640, 60))
	_put(z, "furn_plant", Vector2(110, 800), _depth(800, 48))

# ------------------------------------------------------------- clutter ------

static func _build_clutter(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Clutter"
	parent.add_child(z)
	_put(z, "furn_boxes", Vector2(210, 850), _depth(850, 52))
	_put(z, "furn_boxes", Vector2(300, 900), _depth(900, 52), 0.7)
	# pizza boxes
	for p in [Vector2(880, 800), Vector2(930, 820), Vector2(700, 880)]:
		var box := ColorRect.new()
		box.size = Vector2(46, 40)
		box.position = p
		box.color = Color(0.7, 0.5, 0.25)
		box.z_index = _depth(p.y, 20)
		z.add_child(box)
	# A sad couch nobody sleeps on (drawn from rects)
	_couch(z, Vector2(760, 760))
	# Cable spaghetti from the battlestation to the server corner
	_cable(z, [Vector2(520, 400), Vector2(700, 430), Vector2(950, 380), Vector2(1300, 300)], Color(0.1, 0.1, 0.12))
	_cable(z, [Vector2(1120, 430), Vector2(1250, 380), Vector2(1400, 320)], Color(0.12, 0.11, 0.13))
	_cable(z, [Vector2(300, 300), Vector2(360, 420), Vector2(430, 470)], Color(0.09, 0.09, 0.11))
	# Wall posters (side walls) for depth + jokes
	_poster(z, Vector2(30, 420), Color(0.2, 0.3, 0.5), "IT\nWORKS\nLOCALLY")
	_poster(z, Vector2(30, 620), Color(0.4, 0.2, 0.3), "MOVE\nFAST")
	_poster(z, Vector2(ROOM_W * TILE - 62, 500), Color(0.25, 0.4, 0.35), "SHIP\nOR\nDIE")

static func _couch(parent: Node2D, pos: Vector2) -> void:
	var z := _depth(pos.y, 34)
	var base := Color(0.22, 0.2, 0.3)
	var body := ColorRect.new()
	body.size = Vector2(150, 60)
	body.position = pos - Vector2(75, 20)
	body.color = base
	body.z_index = z
	parent.add_child(body)
	for i in 3:
		var cushion := ColorRect.new()
		cushion.size = Vector2(44, 30)
		cushion.position = pos - Vector2(72 - i * 48, 14)
		cushion.color = base.lightened(0.08)
		cushion.z_index = z + 1
		parent.add_child(cushion)
	# a discarded blanket
	var bl := ColorRect.new()
	bl.size = Vector2(50, 24)
	bl.position = pos - Vector2(10, 6)
	bl.color = Color(0.5, 0.3, 0.35)
	bl.z_index = z + 2
	parent.add_child(bl)

static func _cable(parent: Node2D, points: Array, color: Color) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = color
	line.z_index = -80
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	for p in points:
		line.add_point(p)
	parent.add_child(line)

static func _poster(parent: Node2D, pos: Vector2, color: Color, text: String) -> void:
	var frame := ColorRect.new()
	frame.size = Vector2(44, 60)
	frame.position = pos
	frame.color = color
	frame.z_index = -52
	parent.add_child(frame)
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(5, 6)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	lbl.z_index = -51
	parent.add_child(lbl)

# ------------------------------------------------------------ lighting ------

static func _build_lighting(parent: Node2D) -> void:
	var lamp := PointLight2D.new()
	lamp.texture = _radial()
	lamp.energy = 0.5
	lamp.color = Color(1.0, 0.72, 0.4)
	lamp.texture_scale = 4.0
	lamp.position = Vector2(300, 250)
	parent.add_child(lamp)

static func _radial() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

# -------------------------------------------------------------- signs -------

static func _build_signs(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	_sign(z, Vector2(1360, 120), "SERVER RACK\n(do NOT reboot)", Color(0.5, 1.0, 0.6))
	_sign(z, Vector2(70, 150), "FRIDGE\n(energy drinks only)", Color(0.6, 0.9, 1.0))
	_sign(z, Vector2(200, 200), "COFFEE: MISSION CRITICAL", Color(1.0, 0.78, 0.4))
	_sign(z, Vector2(90, 760), "PLANT\nstatus: deprecated", Color(0.6, 0.8, 0.5))
	_sign(z, Vector2(150, 900), "node_modules\n(trash)", Color(0.7, 0.6, 0.5))
	_sign(z, Vector2(1250, 920), "BED\n'sleep? during a hackathon?'", Color(0.7, 0.75, 0.95))
	_sign(z, Vector2(880, 120), "DNS\nProbably not the problem.", Color(0.55, 0.85, 1.0))

static func _sign(parent: Node2D, pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.z_index = 400
	parent.add_child(lbl)

# ------------------------------------------------------------ gameplay ------

static func _populate_gameplay(parent: Node2D, spawn: Vector2) -> void:
	var tokens := Node2D.new()
	tokens.name = "Tokens"
	parent.add_child(tokens)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	parent.add_child(enemies)
	var npcs := Node2D.new()
	npcs.name = "NPCs"
	parent.add_child(npcs)
	var portals := Node2D.new()
	portals.name = "Portals"
	parent.add_child(portals)
	var props := Node2D.new()
	props.name = "Interactables"
	parent.add_child(props)

	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var token_types := ["common", "common", "cached", "common", "cached"]
	var token_positions := [
		Vector2(420, 640), Vector2(560, 700), Vector2(700, 760),
		Vector2(840, 640), Vector2(980, 700), Vector2(1120, 620),
		Vector2(500, 560), Vector2(760, 520), Vector2(1040, 500),
		Vector2(640, 860), Vector2(900, 900), Vector2(1180, 800),
		Vector2(380, 720), Vector2(1000, 860),
	]
	for i in token_positions.size():
		var t = token_scene.instantiate()
		t.token_type = token_types[i % token_types.size()]
		t.position = token_positions[i]
		tokens.add_child(t)

	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	for pos in [Vector2(1080, 560), Vector2(1180, 760), Vector2(420, 500)]:
		var en = enemy_scene.instantiate()
		en.enemy_type = "bug"
		en.max_hp = 20
		en.position = pos
		enemies.add_child(en)

	var npc_scene := preload("res://scenes/world/npc.tscn")
	var claude = npc_scene.instantiate()
	claude.npc_id = "roommate_ai"
	var claude_quests: Array[String] = ["hello_localhost", "tiny_change", "ship_dream_app"]
	claude.quest_ids = claude_quests
	claude.position = Vector2(820, 560)
	npcs.add_child(claude)

	var interact_scene := preload("res://scenes/world/generic_interactable.tscn")
	var email := _add_interact(props, interact_scene, "client_email", Vector2(430, 360), "Check client email")
	email.one_shot = false  # re-checkable inbox running gag
	_add_interact(props, interact_scene, "dream_app_terminal", Vector2(650, 360), "Dream App Terminal")
	_add_interact(props, interact_scene, "deploy_button", Vector2(760, 380), "Deploy To Production")

	if GameManager.is_region_unlocked("dependency_district"):
		var portal_scene := preload("res://scenes/world/region_portal.tscn")
		var p = portal_scene.instantiate()
		p.target_region = "dependency_district"
		p.portal_label = "Dependency District"
		p.position = Vector2(ROOM_W * TILE - 90, ROOM_H * TILE * 0.5)
		portals.add_child(p)

static func _add_interact(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> Node:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	parent.add_child(node)
	return node
