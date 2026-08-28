extends RefCounted
class_name LocalhostBuilder
## Hand-crafted 3AM coder apartment — cramped, lived-in, tech-noir comedy.

const TILE_SCALE := 4.0
const TILE_PX := 16.0 * TILE_SCALE
const ROOM_W := 30
const ROOM_H := 18

const TILE_DIR := "res://assets/external/kenney/tiny-town/Tiles/"

static func build(parent: Node2D) -> Dictionary:
	parent.y_sort_enabled = true
	var spawn := Vector2(ROOM_W * TILE_PX * 0.35, ROOM_H * TILE_PX * 0.72)
	_build_floor(parent)
	_build_walls(parent)
	_build_lighting(parent)
	_build_furniture(parent)
	_build_props(parent)
	_build_labels(parent)
	_populate_gameplay(parent, spawn)
	return {"spawn": spawn, "size": Vector2(ROOM_W, ROOM_H) * TILE_PX}

static func _tile_pos(gx: int, gy: int) -> Vector2:
	return Vector2(gx * TILE_PX + TILE_PX * 0.5, gy * TILE_PX + TILE_PX * 0.5)

static func _add_tile(parent: Node2D, tile_id: String, gx: int, gy: int, modulate: Color = Color.WHITE, z: int = -10) -> Sprite2D:
	var path := TILE_DIR + tile_id + ".png"
	if not ResourceLoader.exists(path):
		return null
	var s := Sprite2D.new()
	s.texture = load(path)
	s.position = _tile_pos(gx, gy)
	s.scale = Vector2(TILE_SCALE, TILE_SCALE)
	s.modulate = modulate
	s.z_index = z
	parent.add_child(s)
	return s

static func _add_sprite(parent: Node2D, tile_id: String, pos: Vector2, modulate: Color = Color.WHITE, scale: float = TILE_SCALE, z: int = 0) -> Sprite2D:
	var path := TILE_DIR + tile_id + ".png"
	if not ResourceLoader.exists(path):
		return null
	var s := Sprite2D.new()
	s.texture = load(path)
	s.position = pos
	s.scale = Vector2(scale, scale)
	s.modulate = modulate
	s.z_index = z
	parent.add_child(s)
	return s

static func _build_floor(parent: Node2D) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	floor.z_index = -20
	parent.add_child(floor)
	var wood := Color(0.35, 0.28, 0.22)
	var rug := Color(0.22, 0.2, 0.28)
	for gx in ROOM_W:
		for gy in ROOM_H:
			var c := wood.darkened(0.05 * ((gx + gy) % 3))
			if gx >= 14 and gy <= 5:
				c = rug
			_add_tile(floor, "tile_0001" if (gx + gy) % 2 == 0 else "tile_0002", gx, gy, c, -10)

static func _build_walls(parent: Node2D) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var wall_c := Color(0.18, 0.16, 0.22)
	for gx in ROOM_W:
		_add_wall_collider(parent, _tile_pos(gx, 0))
		_add_wall_collider(parent, _tile_pos(gx, ROOM_H - 1))
		_add_tile(walls, "tile_0048", gx, 0, wall_c, -5)
		_add_tile(walls, "tile_0048", gx, ROOM_H - 1, wall_c.darkened(0.1), -5)
	for gy in ROOM_H:
		_add_wall_collider(parent, _tile_pos(0, gy))
		_add_wall_collider(parent, _tile_pos(ROOM_W - 1, gy))
		_add_tile(walls, "tile_0049", 0, gy, wall_c, -5)
		_add_tile(walls, "tile_0049", ROOM_W - 1, gy, wall_c.darkened(0.1), -5)

static func _add_wall_collider(parent: Node2D, pos: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 32
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_PX, TILE_PX)
	shape.shape = rect
	shape.position = pos
	wall.add_child(shape)
	parent.add_child(wall)

static func _build_lighting(parent: Node2D) -> void:
	var glow := Node2D.new()
	glow.name = "AmbientGlow"
	parent.add_child(glow)
	# Monitor glow pools
	for pos in [Vector2(520, 380), Vector2(680, 360), Vector2(840, 380)]:
		var light := PointLight2D.new()
		light.texture = _make_radial_texture()
		light.energy = 0.9
		light.color = Color(0.4, 0.75, 1.0, 1.0)
		light.texture_scale = 2.5
		light.position = pos
		light.shadow_enabled = false
		glow.add_child(light)
	# Warm desk lamp
	var lamp := PointLight2D.new()
	lamp.texture = _make_radial_texture()
	lamp.energy = 0.6
	lamp.color = Color(1.0, 0.7, 0.35, 1.0)
	lamp.texture_scale = 3.0
	lamp.position = Vector2(560, 520)
	glow.add_child(lamp)

static func _make_radial_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

static func _build_furniture(parent: Node2D) -> void:
	var furn := Node2D.new()
	furn.name = "Furniture"
	furn.z_index = 0
	parent.add_child(furn)
	# Desk row — monitors, keyboard clutter
	for i in 3:
		_add_sprite(furn, "tile_0088", Vector2(480 + i * 160, 340), Color(0.15, 0.18, 0.25), TILE_SCALE * 1.2, 2)
		_add_monitor_glow(furn, Vector2(480 + i * 160, 300))
	# Server rack corner
	for row in 3:
		_add_sprite(furn, "tile_0056", Vector2(1200, 200 + row * 70), Color(0.25, 0.28, 0.32), TILE_SCALE * 1.4, 1)
	_add_sprite(furn, "tile_0120", Vector2(1200, 140), Color(0.3, 0.85, 0.5), TILE_SCALE, 3)
	# Pizza boxes
	_add_sprite(furn, "tile_0108", Vector2(900, 680), Color(0.85, 0.55, 0.2), TILE_SCALE, 1)
	_add_sprite(furn, "tile_0108", Vector2(940, 690), Color(0.75, 0.45, 0.15), TILE_SCALE * 0.9, 1)
	# Coffee mug / potion stand-in
	_add_sprite(furn, "tile_0116", Vector2(420, 520), Color(0.9, 0.85, 0.7), TILE_SCALE, 2)
	# Chair
	_add_sprite(furn, "tile_0096", Vector2(620, 580), Color(0.4, 0.35, 0.5), TILE_SCALE, 1)
	# GPU boxes (crate tiles)
	_add_sprite(furn, "tile_0100", Vector2(1050, 750), Color(0.2, 0.6, 0.9), TILE_SCALE * 1.1, 1)
	_add_sprite(furn, "tile_0100", Vector2(1120, 760), Color(0.9, 0.3, 0.2), TILE_SCALE, 1)
	# Cable mess (fence bits)
	_add_sprite(furn, "tile_0072", Vector2(750, 620), Color(0.3, 0.3, 0.35), TILE_SCALE * 0.8, 0)
	_add_sprite(furn, "tile_0073", Vector2(800, 640), Color(0.25, 0.25, 0.3), TILE_SCALE * 0.8, 0)

static func _add_monitor_glow(parent: Node2D, pos: Vector2) -> void:
	var m := ColorRect.new()
	m.size = Vector2(48, 36)
	m.position = pos - m.size * 0.5
	m.color = Color(0.2, 0.85, 0.95, 0.85)
	m.z_index = 3
	parent.add_child(m)

static func _build_props(parent: Node2D) -> void:
	var props := Node2D.new()
	props.name = "Props"
	parent.add_child(props)
	# Sticky notes on wall
	_add_sticky_note(props, Vector2(200, 180), "SHIP\nIT", Color(1.0, 0.95, 0.4))
	_add_sticky_note(props, Vector2(280, 200), "TODO:\neverything", Color(0.9, 0.7, 0.9))
	_add_sticky_note(props, Vector2(350, 170), "call mom\n(later)", Color(0.7, 0.95, 0.7))
	_add_sticky_note(props, Vector2(420, 190), "TODO:\nBACKUPS", Color(1.0, 0.85, 0.5))
	_add_sticky_note(props, Vector2(420, 250), "TODO:\nSERIOUSLY, BACKUPS", Color(1.0, 0.6, 0.6))
	# Whiteboard
	var board := ColorRect.new()
	board.size = Vector2(180, 100)
	board.position = Vector2(150, 250)
	board.color = Color(0.92, 0.92, 0.88, 1.0)
	board.z_index = -2
	props.add_child(board)
	var board_label := Label.new()
	board_label.text = "Architecture:\nBrowser -> API -> K8s -> 17 microservices\nPurpose: SHOPPING LIST"
	board_label.position = Vector2(160, 260)
	board_label.add_theme_font_size_override("font_size", 11)
	board_label.add_theme_color_override("font_color", Color(0.2, 0.15, 0.3))
	board_label.z_index = -1
	props.add_child(board_label)

static func _add_sticky_note(parent: Node2D, pos: Vector2, text: String, color: Color) -> void:
	var note := ColorRect.new()
	note.size = Vector2(56, 56)
	note.position = pos
	note.color = color
	note.z_index = 1
	parent.add_child(note)
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(4, 4)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.1, 0.2))
	lbl.z_index = 2
	parent.add_child(lbl)

static func _build_labels(parent: Node2D) -> void:
	var labels := Node2D.new()
	labels.name = "Signs"
	parent.add_child(labels)
	_add_sign(labels, Vector2(1180, 120), "SERVER RACK\n(please don't reboot)", Color(0.5, 1.0, 0.6))
	_add_sign(labels, Vector2(480, 420), "triple monitor setup\nstill not enough context", Color(0.6, 0.8, 1.0))
	_add_sign(labels, Vector2(200, 420), "PRODUCTION\nNO TESTING BEYOND THIS POINT", Color(1.0, 0.4, 0.35))
	_add_sign(labels, Vector2(1050, 120), "TODO APP\n(powered by hope)", Color(0.4, 0.9, 0.7))
	_add_sign(labels, Vector2(300, 680), "node_modules\n(trash bin)", Color(0.7, 0.6, 0.5))
	_add_sign(labels, Vector2(400, 120), "DNS\nProbably not the problem.", Color(0.5, 0.85, 1.0))
	_add_sign(labels, Vector2(1280, 680), "COFFEE MACHINE\nMISSION CRITICAL", Color(1.0, 0.75, 0.35))

static func _add_sign(parent: Node2D, pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.z_index = 5
	parent.add_child(lbl)

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
		Vector2(350, 550), Vector2(750, 480), Vector2(950, 420),
		Vector2(1100, 550), Vector2(600, 750), Vector2(850, 680),
		Vector2(450, 350), Vector2(1000, 350), Vector2(1300, 600),
		Vector2(500, 850), Vector2(700, 900), Vector2(900, 820),
		Vector2(1050, 450), Vector2(380, 700), Vector2(1280, 780),
	]
	for i in token_positions.size():
		var t = token_scene.instantiate()
		t.token_type = token_types[i % token_types.size()]
		t.position = token_positions[i]
		tokens.add_child(t)

	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	for pos in [Vector2(980, 620), Vector2(1150, 850), Vector2(720, 820)]:
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
	claude.position = Vector2(820, 480)
	npcs.add_child(claude)

	var interact_scene := preload("res://scenes/world/generic_interactable.tscn")
	_add_interact(props, interact_scene, "client_email", Vector2(560, 460), "Check client email")
	_add_interact(props, interact_scene, "dream_app_terminal", Vector2(720, 420), "Dream App Terminal")
	_add_interact(props, interact_scene, "deploy_button", Vector2(900, 460), "Deploy To Production")

	# Portal hidden until later — still present but labeled as locked
	if GameManager.is_region_unlocked("dependency_district"):
		var portal_scene := preload("res://scenes/world/region_portal.tscn")
		var p = portal_scene.instantiate()
		p.target_region = "dependency_district"
		p.portal_label = "Dependency District (not ready yet)"
		p.position = Vector2(ROOM_W * TILE_PX - 120, ROOM_H * TILE_PX * 0.5)
		portals.add_child(p)

static func _add_interact(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> void:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	parent.add_child(node)
