extends Node2D
class_name RegionBuilder

const _LocalhostBuilder = preload("res://scripts/world/localhost_builder.gd")

## Procedurally builds a region from data at runtime.

const REGION_TILE_MAP := {
	"localhost": "localhost",
	"dependency_district": "dependency",
	"stackoverflow_ruins": "stackoverflow",
	"api_bazaar": "api_bazaar",
	"cloud_district": "cloud",
	"open_source_wildlands": "opensource",
	"corporate_enterprise": "corporate",
	"gpu_mines": "gpu",
	"production": "production",
	"token_vault": "vault",
}

const REGION_SIZE := Vector2i(20, 15)
const TILE_SIZE := 64

static func build(parent: Node2D, region_id: String) -> Dictionary:
	if region_id == "localhost":
		return _LocalhostBuilder.build(parent)
	return _build_region_static(parent, region_id)

static func _build_region_static(parent: Node2D, region_id: String) -> Dictionary:
	var tile_name: String = REGION_TILE_MAP.get(region_id, "localhost")
	var tile_tex: Texture2D = load("res://assets/textures/generated/tile_%s.png" % tile_name)
	var spawn_pos := Vector2(REGION_SIZE.x * TILE_SIZE * 0.5, REGION_SIZE.y * TILE_SIZE * 0.5)
	
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var sprite := Sprite2D.new()
			sprite.texture = tile_tex
			sprite.position = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			sprite.z_index = -10
			floor.add_child(sprite)
			if x == 0 or y == 0 or x == REGION_SIZE.x - 1 or y == REGION_SIZE.y - 1:
				_add_wall(parent, sprite.position)
	
	var props := Node2D.new()
	props.name = "Props"
	parent.add_child(props)
	
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	parent.add_child(enemies)
	
	var tokens := Node2D.new()
	tokens.name = "Tokens"
	parent.add_child(tokens)
	
	var npcs := Node2D.new()
	npcs.name = "NPCs"
	parent.add_child(npcs)
	
	var portals := Node2D.new()
	portals.name = "Portals"
	parent.add_child(portals)
	
	_populate_region(region_id, props, enemies, tokens, npcs, portals, spawn_pos)
	
	return {"spawn": spawn_pos, "size": Vector2(REGION_SIZE) * TILE_SIZE}

static func _add_wall(parent: Node2D, pos: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 32
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	shape.position = pos
	wall.add_child(shape)
	parent.add_child(wall)

static func _populate_region(region_id: String, props: Node2D, enemies: Node2D, tokens: Node2D, npcs: Node2D, portals: Node2D, spawn: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	var npc_scene := preload("res://scenes/world/npc.tscn")
	var portal_scene := preload("res://scenes/world/region_portal.tscn")
	
	# Scatter tokens
	var token_count := 25
	var token_types := _region_token_types(region_id)
	for i in token_count:
		var t = token_scene.instantiate()
		t.token_type = token_types[rng.randi() % token_types.size()]
		t.position = _random_pos(rng, spawn)
		tokens.add_child(t)
	
	# Scatter enemies
	var enemy_types := _region_enemies(region_id)
	for e in enemy_types:
		var count: int = e.get("count", 2)
		for i in count:
			var en = enemy_scene.instantiate()
			en.enemy_type = e.type
			en.max_hp = e.get("hp", 30)
			en.position = _random_pos(rng, spawn, 200)
			enemies.add_child(en)
	
	# NPCs
	for npc_data in _region_npcs(region_id):
		var n = npc_scene.instantiate()
		n.npc_id = npc_data.id
		n.quest_ids = npc_data.get("quests", [])
		n.position = npc_data.pos
		npcs.add_child(n)
	
	# Region-specific interactables
	_add_interactables(region_id, props, spawn)
	
	# Portals to connected regions
	for portal_data in _region_portals(region_id):
		if GameManager.is_region_unlocked(portal_data.to) or portal_data.get("always_open", false):
			var p = portal_scene.instantiate()
			p.target_region = portal_data.to
			p.portal_label = portal_data.get("label", portal_data.to)
			p.position = portal_data.pos
			portals.add_child(p)

static func _random_pos(rng: RandomNumberGenerator, center: Vector2, min_dist: float = 80.0) -> Vector2:
	for attempt in 50:
		var pos := Vector2(
			rng.randf_range(TILE_SIZE * 2, (REGION_SIZE.x - 2) * TILE_SIZE),
			rng.randf_range(TILE_SIZE * 2, (REGION_SIZE.y - 2) * TILE_SIZE)
		)
		if pos.distance_to(center) > min_dist:
			return pos
	return center + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))

static func _region_token_types(region_id: String) -> Array:
	match region_id:
		"localhost": return ["common", "common", "cached"]
		"stackoverflow_ruins": return ["cached", "cached", "common"]
		"api_bazaar": return ["premium", "common", "premium"]
		"gpu_mines": return ["compute", "compute", "common"]
		"token_vault": return ["golden", "frontier", "premium"]
		"cloud_district": return ["premium", "compute", "common"]
		_: return ["common", "cached"]

static func _region_enemies(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"type": "bug", "count": 3, "hp": 20}]
		"dependency_district":
			return [{"type": "dependency_demon", "count": 4}, {"type": "null_reference", "count": 3}]
		"stackoverflow_ruins":
			return [{"type": "bug", "count": 3}, {"type": "merge_conflict", "count": 1, "hp": 80}]
		"api_bazaar":
			return [{"type": "rate_limiter", "count": 3}, {"type": "bug", "count": 2}]
		"cloud_district":
			return [{"type": "cloud_bill", "count": 1, "hp": 100}, {"type": "memory_leak", "count": 2}]
		"open_source_wildlands":
			return [{"type": "legacy_system", "count": 2}, {"type": "bug", "count": 3}]
		"corporate_enterprise":
			return [{"type": "enterprise_architect", "count": 1, "hp": 120}, {"type": "scope_creep", "count": 3}]
		"gpu_mines":
			return [{"type": "memory_leak", "count": 5}, {"type": "bug", "count": 2}]
		"production":
			return [{"type": "legacy_monolith", "count": 1, "hp": 200}, {"type": "hallucination", "count": 3}]
		"token_vault":
			return [{"type": "rate_limiter", "count": 2}, {"type": "infinite_context", "count": 1, "hp": 150}]
		_: return [{"type": "bug", "count": 2}]

static func _region_npcs(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"id": "roommate_ai", "pos": Vector2(1200, 900), "quests": ["hello_localhost", "tiny_change", "ship_dream_app"]}]
		"dependency_district":
			return [{"id": "maintainer", "pos": Vector2(1100, 800), "quests": ["install_node", "fix_without_touching"]}]
		"stackoverflow_ruins":
			return [{"id": "stackoverflow_hermit", "pos": Vector2(1000, 700), "quests": ["stackoverflow_pilgrimage", "merge_conflict_hell"]}]
		"api_bazaar":
			return [{"id": "api_reseller", "pos": Vector2(1300, 850), "quests": ["one_more_api_call", "junior_agent"]}, {"id": "junior_agent", "pos": Vector2(800, 600), "quests": ["junior_agent"]}]
		"cloud_district":
			return [{"id": "cloud_salesperson", "pos": Vector2(1200, 750), "quests": ["cloud_migration", "context_window_full"]}]
		"open_source_wildlands":
			return [{"id": "oss_maintainer", "pos": Vector2(1100, 900), "quests": ["license_puzzle"]}]
		"corporate_enterprise":
			return [{"id": "svp_ai", "pos": Vector2(1000, 800), "quests": ["enterprise_ready"]}]
		"gpu_mines":
			return [{"id": "gpu_foreman", "pos": Vector2(1200, 700), "quests": ["gpu_rush"]}]
		"production":
			return [{"id": "oncall_engineer", "pos": Vector2(1100, 850), "quests": ["production_down"]}]
		_: return []

static func _region_portals(region_id: String) -> Array:
	var cx := REGION_SIZE.x * TILE_SIZE * 0.5
	var cy := REGION_SIZE.y * TILE_SIZE * 0.5
	match region_id:
		"localhost":
			return [{"to": "dependency_district", "pos": Vector2(cx + 400, cy), "label": "Dependency District"}]
		"dependency_district":
			return [
				{"to": "localhost", "pos": Vector2(cx - 400, cy), "label": "Localhost"},
				{"to": "stackoverflow_ruins", "pos": Vector2(cx + 400, cy), "label": "Stack Overflow Ruins"},
			]
		"stackoverflow_ruins":
			return [
				{"to": "dependency_district", "pos": Vector2(cx - 400, cy), "label": "Dependency District"},
				{"to": "api_bazaar", "pos": Vector2(cx + 400, cy), "label": "API Bazaar"},
			]
		"api_bazaar":
			return [
				{"to": "stackoverflow_ruins", "pos": Vector2(cx - 400, cy), "label": "Stack Overflow Ruins"},
				{"to": "cloud_district", "pos": Vector2(cx + 400, cy), "label": "Cloud District"},
			]
		"cloud_district":
			return [
				{"to": "api_bazaar", "pos": Vector2(cx - 400, cy), "label": "API Bazaar"},
				{"to": "open_source_wildlands", "pos": Vector2(cx + 400, cy), "label": "Open Source Wildlands"},
			]
		"open_source_wildlands":
			return [
				{"to": "cloud_district", "pos": Vector2(cx - 400, cy), "label": "Cloud District"},
				{"to": "corporate_enterprise", "pos": Vector2(cx + 400, cy), "label": "Corporate Enterprise"},
			]
		"corporate_enterprise":
			return [
				{"to": "open_source_wildlands", "pos": Vector2(cx - 400, cy), "label": "Open Source Wildlands"},
				{"to": "gpu_mines", "pos": Vector2(cx + 400, cy), "label": "GPU Mines"},
			]
		"gpu_mines":
			return [
				{"to": "corporate_enterprise", "pos": Vector2(cx - 400, cy), "label": "Corporate Enterprise"},
				{"to": "production", "pos": Vector2(cx + 400, cy), "label": "Production"},
			]
		"production":
			return [
				{"to": "gpu_mines", "pos": Vector2(cx - 400, cy), "label": "GPU Mines"},
				{"to": "token_vault", "pos": Vector2(cx + 400, cy), "label": "Token Vault"},
			]
		"token_vault":
			return [
				{"to": "production", "pos": Vector2(cx - 400, cy), "label": "Production"},
				{"to": "localhost", "pos": Vector2(cx, cy - 400), "label": "Return to Localhost"},
			]
		_: return []

static func _add_interactables(region_id: String, props: Node2D, _spawn: Vector2) -> void:
	var interact_scene := preload("res://scenes/world/generic_interactable.tscn")
	match region_id:
		"localhost":
			_add_prop(props, interact_scene, "client_email", Vector2(900, 700), "Check client email")
			_add_prop(props, interact_scene, "dream_app_terminal", Vector2(1400, 800), "Dream App Terminal")
			_add_prop(props, interact_scene, "deploy_button", Vector2(1500, 900), "Deploy To Production")
		"dependency_district":
			_add_prop(props, interact_scene, "abandoned_package", Vector2(1000, 600), "Recover package")
		"api_bazaar":
			_add_prop(props, interact_scene, "backup_server", Vector2(1400, 700), "Backup Server")

static func _add_prop(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> void:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	parent.add_child(node)
