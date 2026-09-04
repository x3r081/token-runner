class_name ActorProxy
extends Node2D
## Shadow proxy (3D_BIBLE.md §5). A hidden Node2D that stands in for a 3D
## actor wherever the UI reads actors by group and Vector2 position:
## objective_waypoint.gd, guide_overlay.gd, quest resolvers. The host keeps
## `global_position` in MAP PIXELS via sync() each frame.

var host: Node3D

# Mirrored fields — typed so `"npc_id" in proxy` style checks succeed.
var npc_id: String = ""
var quest_ids: Array[String] = []
var token_type: String = ""
var amount: int = 0
var collected: bool = false
var target_region: String = ""
var portal_label: String = ""
var interact_id: String = ""
var interact_text: String = ""
var enemy_type: String = ""
var hp: int = 0
var max_hp: int = 0
var is_boss: bool = false

const ROOT_GROUP := "proxy_root"

static func attach(h: Node3D, groups: Array, fields: Dictionary = {}) -> ActorProxy:
	var p := ActorProxy.new()
	p.name = "Proxy_" + h.name
	p.host = h
	p.visible = false
	for g in groups:
		p.add_to_group(str(g))
	for k in fields:
		p.set_field(str(k), fields[k])
	var tree := h.get_tree()
	var root: Node = tree.get_first_node_in_group(ROOT_GROUP) if tree else null
	if root == null:
		root = tree.current_scene if tree and tree.current_scene else h
	root.add_child(p)
	h.tree_exiting.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
	p.sync()
	return p

func set_field(key: String, value) -> void:
	if key in self:
		set(key, value)

## Keep the 2D twin where the 3D body is (map px).
func sync() -> void:
	if is_instance_valid(host):
		global_position = Map3D.to_map(host.global_position)

## `get_prompt()` / `interact()` forwarded so UI code that probes methods on a
## group member behaves the same as with a 2D actor.
func get_prompt() -> String:
	if is_instance_valid(host) and host.has_method("get_prompt"):
		return host.get_prompt()
	return interact_text

func interact(player: Node) -> void:
	if is_instance_valid(host) and host.has_method("interact"):
		host.interact(player)
