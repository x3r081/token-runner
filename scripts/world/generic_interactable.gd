extends "res://scripts/world/interactable.gd"

var _breath_t := 0.0
var _glow_gate := 0.0

const GLOW_RADIUS := 110.0

func _ready() -> void:
	super._ready()
	_breath_t = randf() * TAU  # desync so props don't inhale in unison

## Gentle breathing glow when the player is close: interactable props quietly
## brighten and dim, and the [E] prompt (player-side) fades in on top of this.
func _process(delta: float) -> void:
	_breath_t += delta
	var near := false
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) < GLOW_RADIUS:
		near = true
	_glow_gate = move_toward(_glow_gate, 1.0 if near else 0.0, delta * 4.0)
	if _glow_gate <= 0.001:
		if modulate != Color.WHITE:
			modulate = Color.WHITE
		return
	var b := (0.5 + 0.5 * sin(_breath_t * 2.6)) * _glow_gate
	modulate = Color(1.0 + b * 0.35, 1.0 + b * 0.3, 1.0 + b * 0.18)

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

	# --- Dependency District ---
	"prop_node_modules": ["node_modules/", "1.2 GB. Four (4) files you use; forty thousand you pray never break.\nIt has its own gravity now. Small moons orbit it."],
	"prop_leftpad": ["left-pad", "Eleven lines of code.\nOnce took down half the internet.\nStill more reliable than your auth service."],
	"prop_lockfile": ["package-lock.json", "47,000 lines. Nobody has read it. Nobody ever will.\nIt is load-bearing folklore. Do not 'git blame' it. It blames back."],
	# --- API Bazaar ---
	"prop_api_stall": ["API Reseller Stall", "'FREE tier: 3 requests/month.\nPRO tier: also 3, but you feel better about it.'"],
	"prop_status_page": ["Status Page", "\u2705 All systems operational.\n(This page is cached. From June. It is not June.)"],
	"prop_pricing": ["Pricing Board", "Pay-as-you-go!\nGo where, exactly?\n...bankrupt. The answer is bankrupt."],
	# --- Stack Overflow Ruins ---
	"prop_gravestone": ["Gravestone", "Here lies a Question.\n'Closed as opinion-based.'\n2011 \u2013 2011. It had so much to ask."],
	"prop_accepted": ["Accepted Answer", "Score: 4,201. Written in a language deprecated in 2014.\nStill the #1 result. Still the only thing that works."],
	# --- Cloud District ---
	"prop_invoice": ["Cloud Invoice", "This month: 'successful adoption.'\n\u20ac4,207.\nYou ran one (1) cron job. It printed 'hello'."],
	"prop_dashboard": ["Cloud Dashboard", "94 services provisioned.\nYou use 2.\nThe other 92 are 'strategic'. And billing."],
	# --- GPU Mines ---
	"prop_rig": ["Mining Rig", "Hashing? Training? Rendering?\nHonestly nobody remembers anymore.\nIt is warm and it is expensive. That much is certain."],
	"prop_fan": ["Cooling Fan", "Decibels: jet engine.\nEffectiveness: largely spiritual."],
	# --- Open Source Wildlands ---
	"prop_sponsor": ["Sponsor Button", "11 years. 40M downloads/month.\nSponsorship: $7/month and one (1) thumbs-up react.\nThe maintainer has seen things."],
	"prop_issue": ["Open Issue #4092", "'URGENT: doesn't work.'\nNo repro. No version. No logs. No mercy.\nFiled 3 years ago. Assigned to: nobody. Ever."],
	# --- Corporate Enterprise ---
	"prop_mission": ["Mission Statement", "'To synergize AI-first paradigms at hyperscale.'\nFramed. Backlit. Gold leaf.\nMeans nothing. Cost \u20ac40k."],
	"prop_kanban": ["Kanban Board", "'In Progress': 47 tickets.\n'Done': 0.\n'Blocked': everything, spiritually."],
	# --- Production ---
	"prop_pager": ["On-Call Pager", "3 missed pages.\nOne during your own wedding.\nIt buzzes again. It always buzzes again."],
	"prop_runbook": ["Incident Runbook", "Step 1: Don't panic.\nStep 2: Panic.\nStep 3: Blame DNS.\nStep 4: It was DNS."],
	# --- Token Vault ---
	"prop_vault": ["Token Vault", "Balance: enough for one (1) frontier prompt, OR a week of the local 7B.\nChoose wisely. The vault is judging you."],
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
