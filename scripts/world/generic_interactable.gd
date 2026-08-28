extends "res://scripts/world/interactable.gd"

func _on_interact(_player: Node) -> void:
	match interact_id:
		"deploy_button":
			if GameManager.can_ship():
				GameManager.trigger_victory()
				var victory := preload("res://scenes/ui/victory_screen.tscn").instantiate()
				get_tree().current_scene.add_child(victory)
			else:
				_show_message("Dream App not ready. Check upgrade requirements (B key).")
		"dream_app_terminal":
			_show_message("Open Dream App panel with [B] to upgrade.")
		"client_email":
			_show_message("Subject: RE: RE: RE: One tiny change\n\n'Can you also make the logo bigger?'")
		"abandoned_package":
			_show_message("Package recovered. 47 vulnerabilities included free.")
		"backup_server":
			_show_message("Agent escorted to backup server. Database restored. Probably.")

func _show_message(text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = text
	dlg.title = "System Message"
	get_tree().root.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
