extends "res://scripts/world/interactable.gd"

func _on_interact(_player: Node) -> void:
	match interact_id:
		"deploy_button":
			if GameManager.can_ship():
				GameManager.trigger_victory()
				_show_overlay(preload("res://scenes/ui/victory_screen.tscn").instantiate())
			else:
				_show_message("Dream App not ready. Check upgrade requirements (B key).")
		"dream_app_terminal":
			if EventManager.has_active_event():
				return
			# Architecture decisions console (repeatable until all decided).
			EventManager.start_scripted("menu_arch", ArchitectureManager.menu_stages(), true)
		"client_email":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("tiny_change"):
				_show_message("Inbox: 3,918 unread.\n\n'Hey, tiny thing — can you make the logo bigger? And also smaller?'")
			else:
				EventManager.start_scripted("tiny_change", preload("res://scripts/world/story_events.gd").tiny_change())
		"free_tokens_ad":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("free_tier"):
				_show_message("The ad returns: 'Your FREE tokens expired. Claim 10,000 MORE?*'\n\n*conditions apply, obviously.")
			else:
				EventManager.start_scripted("free_tier", preload("res://scripts/world/story_events.gd").free_tier())
		"broken_service":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("debugging_investigation"):
				_show_message("/checkout is stable. For now. Suspiciously stable.")
			else:
				EventManager.start_scripted("debugging_investigation", preload("res://scripts/world/story_events.gd").debugging_investigation())
		"agent_terminal":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("autonomous_agent"):
				# After the cautionary tale, the terminal becomes a deploy console.
				EventManager.start_scripted("menu_agent", preload("res://scripts/world/story_events.gd").agent_menu(), true)
			else:
				EventManager.start_scripted("autonomous_agent", preload("res://scripts/world/story_events.gd").autonomous_agent())
		"abandoned_package":
			_show_message("Package recovered. 47 vulnerabilities included free.")
		"backup_server":
			_show_message("Agent escorted to backup server. Database restored. Probably.")
		_:
			if FLAVOR.has(interact_id):
				var f: Array = FLAVOR[interact_id]
				_flavor(f[0], f[1])

## Environmental comedy props. [E] on them for a laugh; pure flavor, no stakes
## (except the ones that gently cost Will To Live, because relatability).
const FLAVOR := {
	"prop_fridge": ["Fridge", "Contents: 14 energy drinks, one (1) sad baby carrot, and a yogurt that expired during the last framework migration.\n\nNutrition: technically."],
	"prop_plant": ["Potted Plant", "Status: DEPRECATED.\nLast watered: v0.3.0.\nStill more alive than the roadmap."],
	"prop_bed": ["Bed", "It whispers: 'Sleep...'\nYou: 'Not during a hackathon.'\nThe bed has heard this lie before."],
	"prop_coffee": ["Coffee Machine", "MISSION CRITICAL.\nUptime: 100%. Ships to prod flawlessly.\nUnlike literally everything else you have built."],
	"prop_router": ["Router", "Four lights. One is blinking wrong.\nDNS: it's not DNS.\n...it's always DNS.\nEither way: somehow your fault."],
	"prop_terminal": ["Terminal", "$ npm audit\n\n847 vulnerabilities (312 high, 61 critical)\n0 addressed.\n\nConfidence: restored."],
	"prop_whiteboard": ["Whiteboard", "'MVP ARCHITECTURE'\nApproximately 38 arrows. Two boxes labeled '???'. One labeled 'here be dragons'.\n\nA red arrow loops back to itself. Nobody remembers why."],
	"prop_monitors": ["Battlestation", "Monitor 1: TOKEN BALANCE: dangerously low.\nMonitor 2: AI SUBSCRIPTIONS: 8 active.\nMonitor 3: MONTHLY SAVINGS FROM AI: -€713.\n\nThe math is not mathing."],
	"prop_sticker": ["Laptop Lid", "Stickers: a raccoon, three defunct startups, and one that just says 'I USE ARCH BTW'.\n\nThe laptop runs, in fact, on spite."],
	"prop_server": ["Server Rack", "A tower of consumer GPUs held together by zip ties and denial.\nGPU 3 is at 94\u00b0C and 'fine'.\nIt is not fine. It is space-heater-in-July fine."],
}

func _show_overlay(node: Node) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("show_overlay"):
		scene.show_overlay(node)
	elif scene:
		scene.add_child(node)

func _flavor(title: String, text: String) -> void:
	var popup = preload("res://scenes/ui/flavor_popup.tscn").instantiate()
	popup.title_text = title
	popup.body_text = text
	_show_overlay(popup)

func _show_message(text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = text
	dlg.title = "System Message"
	get_tree().root.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
