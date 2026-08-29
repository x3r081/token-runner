extends "res://scripts/world/interactable.gd"

const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

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
				_show_message(_deploy_blocked_text(), "Deploy Button")
		"dream_app_terminal":
			if EventManager.has_active_event():
				return
			# Architecture decisions console (repeatable until all decided).
			EventManager.start_scripted("menu_arch", ArchitectureManager.menu_stages(), true)
		"client_email":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("tiny_change"):
				_show_message(_Comedy.pick("client_email", CLIENT_EMAILS), "Inbox")
			else:
				EventManager.start_scripted("tiny_change", preload("res://scripts/world/story_events.gd").tiny_change())
		"free_tokens_ad":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("free_tier"):
				_show_message(_Comedy.pick("free_ad", FREE_TOKEN_ADS), "Pop-up Ad")
			else:
				EventManager.start_scripted("free_tier", preload("res://scripts/world/story_events.gd").free_tier())
		"broken_service":
			if EventManager.has_active_event():
				return
			if EventManager.is_script_completed("debugging_investigation"):
				_show_message(_Comedy.pick("broken_svc", CHECKOUT_STATUS), "/checkout")
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
			_show_message("Package recovered.\n\nIncluded free: 47 known vulnerabilities, two abandoned transitive dependencies, and a post-install script that 'just checks for updates'.\n\nYou did not read the post-install script. Nobody has ever read the post-install script.", "Abandoned Package")
		"backup_server":
			_show_message("The Junior Agent has been escorted to the backup server.\n\nDatabase restored from a snapshot taken 40 minutes ago. Everything after that is now folklore.\n\nThe agent is already 100% confident about the next thing.", "Backup Server")
		_:
			if FLAVOR.has(interact_id):
				_flavor_for(interact_id)

## The deploy button must never just say "no". It says no, then says exactly
## which requirement is missing and which key opens the place to fix it.
func _deploy_blocked_text() -> String:
	var req := DreamAppManager.get_ship_requirements()
	var rows: Array[String] = []
	for entry: Array in [
			["Features", req.features], ["Stability", req.stability],
			["Total upgrades", req.total_upgrades], ["AI tier", req.ai_tier],
			["Infrastructure tier", req.infra_tier]]:
		var d: Dictionary = entry[1]
		if int(d.current) < int(d.required):
			rows.append("  ✗ %s %d/%d" % [String(entry[0]), int(d.current), int(d.required)])
	if rows.is_empty():
		rows.append("  ✗ something the checklist knows about and this button does not.")
	return "Deploy blocked. The Dream App is not shippable yet.\n\nOUTSTANDING:\n%s\n\nOpen the Dream App console with [B] and buy the missing upgrades. Tokens come from pickups, quests and defeated bugs.\n\n(Yes, you could ship it anyway. No, you cannot: we added a check. You're welcome.)" % "\n".join(rows)

## Running-gag inboxes, ads and healthchecks — rotated so a repeat visit is a
## new joke rather than the same one louder.
const CLIENT_EMAILS := [
	"Inbox: 3,918 unread.\n\n'Hey, tiny thing — can you make the logo bigger? And also smaller?'",
	"New mail:\n\n'Quick one! Can we add AI? Not sure what for exactly. Investors keep asking.'",
	"New mail:\n\n'Loving the direction! Can it be more like Uber, but for spreadsheets, and also blue?'",
	"New mail:\n\n'Small ask before launch: multi-tenancy, SSO and an audit log. Should be quick, right?'",
	"New mail:\n\n'Forwarding feedback from my nephew, who codes.'\n\nAttached: 4 pages.",
	"New mail. Subject: 'URGENT!!!'\n\nBody: 'nvm sorted it'\n\nSent 03:41. It is 03:42.",
	"New mail:\n\n'Can we pull the deadline forward? The date was fairly arbitrary anyway.'\n\nIt was not arbitrary. You chose it. It was already impossible.",
	"New mail:\n\n'No rush at all!'\n\nSent to: you, your manager, your manager's manager, and legal.",
	"Inbox: 3,921 unread.\n\nThree of them are from you, to yourself, at 2AM, containing only a URL.",
]

const FREE_TOKEN_ADS := [
	"The ad returns: 'Your FREE tokens expired. Claim 10,000 MORE?*'\n\n*conditions apply, obviously.",
	"'CONGRATULATIONS! You are the 1,000,000th visitor to this terminal.'\n\nThe terminal has had four visitors. All of them were you.",
	"'FREE TOKENS — no credit card required!*'\n\n*credit card required at step 4 of 4.",
	"'Limited offer — ends in 00:00:14.'\n\nIt has said fourteen seconds for six hours.",
	"'Your trial has been extended!'\n\nBy nothing. It has been extended by nothing.",
	"'Unlock 10x productivity for €0.'\n\nThe €0 plan does not include inference. Inference is the product.",
	"'You have been selected for early access.'\n\nEveryone has been selected for early access. That is what early access is.",
]

const CHECKOUT_STATUS := [
	"/checkout is stable. For now. Suspiciously stable.",
	"/checkout: 200 OK. p99 latency 4.2s.\n\nTechnically a success. Emotionally a timeout.",
	"/checkout has not errored in twelve minutes — the longest streak this week.\n\nNobody is celebrating. Everybody is watching.",
	"/checkout is fine.\n/checkout has never been fine.\n\nBoth statements are true and both are load-bearing.",
	"/checkout errors only for one customer, only on Tuesdays, only in Belgium.\n\nThe ticket has been open for five months and is titled 'weird one'.",
]

## Environmental comedy props. [E] on them for a laugh; pure flavor, no stakes
## (except the ones that gently cost Will To Live, because relatability).
##
## FORMAT: id -> [title, body_1, body_2, body_3, ...]. Extra bodies are the
## repeat-interaction escalation — look at the same object three times and the
## game gets progressively more worried about you. The last body repeats once
## you run out, but the visit counter keeps climbing in the popup subtitle.
const FLAVOR := {
	"prop_fridge": ["Fridge",
		"Contents: 14 energy drinks, one (1) sad baby carrot, and a yogurt that expired during the last framework migration.\n\nNutrition: technically.",
		"You open it again. The carrot has not improved. The yogurt has developed opinions.\n\nThe little light comes on. Something in you does not.",
		"Third visit. A refrigerator is not a backlog. Nothing new has been deployed to it.\n\nThe yogurt is now the most senior thing in this apartment.",
		"You are using a fridge as a break from a screen you chose to look at.\n\nThe carrot would like to be listed as a co-author."],
	"prop_plant": ["Potted Plant",
		"Status: DEPRECATED.\nLast watered: v0.3.0.\nStill more alive than the roadmap.",
		"You check on it again. It has not photosynthesised in your absence.\n\nIt has, however, outlived two side projects and one startup.",
		"The plant does not need attention. The plant needs water.\n\nThese are famously not the same thing, as several of your relationships could confirm."],
	"prop_bed": ["Bed",
		"It whispers: 'Sleep...'\nYou: 'Not during a hackathon.'\nThe bed has heard this lie before.",
		"The bed says nothing this time. It has moved to passive resistance.\n\nThe pillow is holding a grudge and, somehow, a receipt.",
		"Third approach. The bed is now simply a large soft object you keep visiting and refusing.\n\nIt is 3AM. One of you is being unreasonable, and it is not the furniture."],
	"prop_coffee": ["Coffee Machine",
		"MISSION CRITICAL.\nUptime: 100%. Ships to prod flawlessly.\nUnlike literally everything else you have built.",
		"Cup four. It performs perfectly again — no standup, no roadmap, no retro.\n\nIt is the best engineer in this apartment and it knows it.",
		"You have now consumed enough caffeine to qualify as a distributed system.\n\nConsistency: eventual. Availability: technically. Partition tolerance: emotional."],
	"prop_router": ["Router",
		"Four lights. One is blinking wrong.\nDNS: it's not DNS.\n...it's always DNS.\nEither way: somehow your fault.",
		"You look again. The wrong light is still blinking wrong.\n\nYou consider unplugging it for ten seconds. You know this will work. You resent that it will work.",
		"You unplugged it. It worked. No root cause was found, recorded, or ever will be.\n\nThat gesture is the entire discipline of networking."],
	"prop_terminal": ["Terminal",
		"$ npm audit\n\n847 vulnerabilities (312 high, 61 critical)\n0 addressed.\n\nConfidence: restored.",
		"$ npm audit fix\n\n3 fixed. 12 introduced. Four packages now demand a major version bump 'for security'.\n\nNet vulnerabilities: 856. Progress.",
		"$ npm audit fix --force\n\nThe terminal goes very quiet.\nSomewhere, a lockfile screams.\n\nYou close the tab and agree with yourself that this never happened."],
	"prop_whiteboard": ["Whiteboard",
		"'MVP ARCHITECTURE'\nApproximately 38 arrows. Two boxes labeled '???'. One labeled 'here be dragons'.\n\nA red arrow loops back to itself. Nobody remembers why.",
		"You study it properly this time. Two of the boxes were drawn by someone who has since left the company.\n\nThe red loop is load-bearing. Do not erase the red loop.",
		"You have now looked at this whiteboard for longer than anyone spent designing it.\n\nSomeone has added, in a different pen, in the corner: 'we knew'."],
	"prop_monitors": ["Battlestation",
		"Monitor 1: TOKEN BALANCE: dangerously low.\nMonitor 2: AI SUBSCRIPTIONS: 8 active.\nMonitor 3: MONTHLY SAVINGS FROM AI: -€713.\n\nThe math is not mathing.",
		"Monitor 2 has updated: 9 active subscriptions.\nYou do not remember the ninth. The ninth remembers you.\n\nIt renews on the 3rd.",
		"All three monitors now show the same dashboard, because you were 'consolidating'.\n\nIt is the dashboard nobody reads. It is beautifully rendered."],
	"prop_sticker": ["Laptop Lid",
		"Stickers: a raccoon, three defunct startups, and one that just says 'I USE ARCH BTW'.\n\nThe laptop runs, in fact, on spite.",
		"Under the raccoon there is an older sticker, half-peeled: a company that raised €40M and shipped a landing page.\n\nYou were employee eleven. You still have the hoodie.",
		"You count them again. Four of the six companies no longer exist.\n\nThe laptop outlasted all of them. So, technically, did you."],
	"prop_server": ["Server Rack",
		"A tower of consumer GPUs held together by zip ties and denial.\nGPU 3 is at 94°C and 'fine'.\nIt is not fine. It is space-heater-in-July fine.",
		"GPU 3 is at 96°C. You add another zip tie.\n\nZip ties do not conduct heat away from anything. You knew this before you did it.",
		"GPU 3 has stopped reporting a temperature entirely.\n\nThis is either a sensor fault or the best news of the night. You decide not to investigate — investigating is how outages start."],

	# --- Dependency District ---
	"prop_node_modules": ["node_modules/",
		"1.2 GB. Four (4) files you use; forty thousand you pray never break.\nIt has its own gravity now. Small moons orbit it.",
		"You look again. 1.4 GB. You have installed nothing in between.\n\nIt is growing. No explanation survives contact with a senior engineer.",
		"Somewhere in here is a package whose entire job is to check whether a number is a number.\n\nIt has 61 million weekly downloads and one very tired maintainer."],
	"prop_leftpad": ["left-pad",
		"Eleven lines of code.\nOnce took down half the internet.\nStill more reliable than your auth service.",
		"Eleven lines. You could write it in ninety seconds.\n\nYou will not. Nobody will. That is the actual lesson and the entire industry refuses it.",
		"It sits there, small and calm, having caused more downtime than every architecture review in history has prevented."],
	"prop_lockfile": ["package-lock.json",
		"47,000 lines. Nobody has read it. Nobody ever will.\nIt is load-bearing folklore. Do not 'git blame' it. It blames back.",
		"You open it. Line 12,004 references a package published by an account that has not posted since 2019.\n\nYou close it.",
		"You have now looked at the lockfile three times without changing anything, which remains the correct and only way to interact with a lockfile."],
	# --- API Bazaar ---
	"prop_api_stall": ["API Reseller Stall",
		"'FREE tier: 3 requests/month.\nPRO tier: also 3, but you feel better about it.'",
		"The sign has changed: 'ENTERPRISE tier: contact sales.'\n\nThere is no contact. There is no sales. There is a form.",
		"'FREE tier discontinued. Existing users grandfathered until Friday.'\n\nIt is Friday. It is always Friday here."],
	"prop_status_page": ["Status Page",
		"✅ All systems operational.\n(This page is cached. From June. It is not June.)",
		"✅ All systems operational.\n\nBelow, in 9pt grey: 'Investigating elevated error rates.' Posted four hours ago. Never updated.",
		"The status page is now itself down.\n\nFor the first time all week, it is accurate."],
	"prop_pricing": ["Pricing Board",
		"Pay-as-you-go!\nGo where, exactly?\n...bankrupt. The answer is bankrupt.",
		"A new line item has appeared: 'egress'.\n\nNobody has ever budgeted for egress. Egress has budgeted for you.",
		"The board now reads 'Contact us for pricing', which is this industry's way of saying 'we saw your funding round'."],
	# --- Stack Overflow Ruins ---
	"prop_gravestone": ["Gravestone",
		"Here lies a Question.\n'Closed as opinion-based.'\n2011 – 2011. It had so much to ask.",
		"Beside it, a smaller stone: 'Closed as too broad.'\n\nThe question was four words long.",
		"A third stone, freshly cut: 'Duplicate of a question that was itself closed as a duplicate.'\n\nSomewhere, a loop closes."],
	"prop_accepted": ["Accepted Answer",
		"Score: 4,201. Written in a language deprecated in 2014.\nStill the #1 result. Still the only thing that works.",
		"Top comment, 340 upvotes: 'This no longer works.'\nReply, 890 upvotes: 'It does if you don't upgrade.'\n\nThis is the state of the art.",
		"The author's profile: last seen nine years ago.\n\nThey solved your problem before you had it and then left, which is the most gracious thing anyone has ever done for you."],
	# --- Cloud District ---
	"prop_invoice": ["Cloud Invoice",
		"This month: 'successful adoption.'\n€4,207.\nYou ran one (1) cron job. It printed 'hello'.",
		"The itemised breakdown arrives: 340 line items.\n\nThe largest is called 'Other'. 'Other' is €2,900.",
		"You open a support ticket about the bill.\n\nThe reply recommends engaging a solutions architect. The solutions architect is billable."],
	"prop_dashboard": ["Cloud Dashboard",
		"94 services provisioned.\nYou use 2.\nThe other 92 are 'strategic'. And billing.",
		"You try to delete one. It has six dependencies. Each of those has four.\n\nYou close the tab. This is precisely how the 92 became 92.",
		"There is a service here you have never heard of, created by a Terraform run in March, costing €41 a month, that nobody can identify.\n\nIt is named 'temp'."],
	# --- GPU Mines ---
	"prop_rig": ["Mining Rig",
		"Hashing? Training? Rendering?\nHonestly nobody remembers anymore.\nIt is warm and it is expensive. That much is certain.",
		"A sticky note on the side reads: 'DO NOT STOP — running since Feb'.\n\nNo signature. No job name. No logs.",
		"You hold a hand near it. The heat is genuinely impressive.\n\nIn winter this rig is a heating subsidy. In July it is a moral question."],
	"prop_fan": ["Cooling Fan",
		"Decibels: jet engine.\nEffectiveness: largely spiritual.",
		"Someone has aimed it at the thermometer rather than at the hardware.\n\nThe metric improved immediately. This is called optimising for the KPI.",
		"It has run so long you no longer consciously hear it.\n\nYou will hear it tonight, in bed, forever."],
	# --- Open Source Wildlands ---
	"prop_sponsor": ["Sponsor Button",
		"11 years. 40M downloads/month.\nSponsorship: $7/month and one (1) thumbs-up react.\nThe maintainer has seen things.",
		"A Fortune 500 runs this package in production.\n\nThey have not sponsored. They have filed three issues this quarter.",
		"The README now opens with: 'This project is maintained in my evenings. Please be kind.'\n\nThe newest issue is titled 'URGENT'."],
	"prop_issue": ["Open Issue #4092",
		"'URGENT: doesn't work.'\nNo repro. No version. No logs. No mercy.\nFiled 3 years ago. Assigned to: nobody. Ever.",
		"Someone has commented: '+1'.\nSomeone else: 'any update?'\nThe maintainer, once, two years ago: 'could you share a reproduction?'\n\nSilence.",
		"Auto-closed by a stale-bot, reopened by a stranger, auto-closed again.\n\nIt will outlive the project. It may outlive the language."],
	# --- Corporate Enterprise ---
	"prop_mission": ["Mission Statement",
		"'To synergize AI-first paradigms at hyperscale.'\nFramed. Backlit. Gold leaf.\nMeans nothing. Cost €40k.",
		"A smaller plaque below credits the agency.\n\nThe agency's own website is one page with a video of a drone over a beach.",
		"You read it a third time and, for one horrible second, understand it.\n\nThis is the most alarming thing that has happened to you all night."],
	"prop_kanban": ["Kanban Board",
		"'In Progress': 47 tickets.\n'Done': 0.\n'Blocked': everything, spiritually.",
		"A new column has appeared: 'In Progress (Actually)'.\n\nIt holds three tickets. All three are also still in 'In Progress'.",
		"Someone has added a column called 'Won't Fix (For Now)'.\n\nIt is the only column with velocity."],
	# --- Production ---
	"prop_pager": ["On-Call Pager",
		"3 missed pages.\nOne during your own wedding.\nIt buzzes again. It always buzzes again.",
		"You check the escalation policy.\nPrimary: you.\nSecondary: you.\nManager escalation: also, somehow, you.",
		"It buzzes. False alarm — a healthcheck that has been broken for six months.\n\nNobody will fix it, because fixing it means admitting it exists."],
	"prop_runbook": ["Incident Runbook",
		"Step 1: Don't panic.\nStep 2: Panic.\nStep 3: Blame DNS.\nStep 4: It was DNS.",
		"Step 5, added later in different handwriting: 'If step 4 fails, restart the thing. You know the thing.'\n\nYou do know the thing.",
		"The last page is blank except for one line:\n'If you are reading this at 4AM, it is not your fault, and it is your problem.'\n\nSomebody cared once."],
	# --- Token Vault ---
	"prop_vault": ["Token Vault",
		"Balance: enough for one (1) frontier prompt, OR a week of the local 7B.\nChoose wisely. The vault is judging you.",
		"A small brass plate reads: 'ESTIMATED SPEND THIS MONTH'.\n\nThe number is written in pencil and has been erased four times.",
		"You stare into the vault. The vault stares back and quietly recalculates your burn rate.\n\nIt does not like the trend."],
}

## Repeat-interaction escalation: walk the body list, then let the visit counter
## carry the joke once the list runs out.
func _flavor_for(id: String) -> void:
	var f: Array = FLAVOR[id]
	var visits: int = _Comedy.bump("prop:%s" % id)
	var bodies: Array = f.slice(1)
	if bodies.is_empty():
		bodies = ["..."]
	var idx: int = clampi(visits - 1, 0, bodies.size() - 1)
	_flavor(String(f[0]), String(bodies[idx]), _Comedy.visit_note(visits))

func _show_overlay(node: Node) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("show_overlay"):
		scene.show_overlay(node)
	elif scene:
		scene.add_child(node)

func _flavor(title: String, text: String, subtitle: String = "") -> void:
	var popup = preload("res://scenes/ui/flavor_popup.tscn").instantiate()
	popup.title_text = title
	popup.body_text = text
	popup.subtitle_text = subtitle
	_show_overlay(popup)

## System messages ride the same styled popup as the flavor props: it lives under
## the HUD CanvasLayer (so death clears it), it pauses while you read, and it
## closes on [E]. The old AcceptDialog did none of those things.
func _show_message(text: String, title: String = "System Message") -> void:
	_flavor(title, text)
