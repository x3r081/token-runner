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

func _show_overlay(node: Node) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("show_overlay"):
		scene.show_overlay(node)
	elif scene:
		scene.add_child(node)

func _show_message(text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = text
	dlg.title = "System Message"
	get_tree().root.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
