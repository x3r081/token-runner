extends "res://scripts/world/interactable.gd"

const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _GameTheme = preload("res://scripts/ui/game_theme.gd")

var _breath_t := 0.0
var _glow_gate := 0.0

const GLOW_RADIUS := 110.0
## How far the prop lifts when the player is in range. VISUAL_BIBLE_V2 LAW 3:
## props do not glow. 1.10 is a highlight — enough to say "this one is a lever,
## not scenery" while the [E] prompt fades in over it — where round 5's 1.35 on
## a 2.6 rad/s sine was an overbright pulse that pushed a crate into the same
## brightness band as the player and the objective.
const HIGHLIGHT := 0.10

func _ready() -> void:
	super._ready()
	_breath_t = randf() * TAU  # desync so props don't inhale in unison

## A still highlight when the player is close: interactable props step up once
## and hold, and the [E] prompt (player-side) fades in on top of it. It does NOT
## breathe — LAW 9 allows a light 6% of flicker and a character 1px of breath,
## and a room of pulsing furniture is neither.
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
	var b := HIGHLIGHT * _glow_gate
	modulate = Color(1.0 + b, 1.0 + b, 1.0 + b)

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
		"prop_coffee":
			_coffee_break()
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
			rows.append("  [ ] %s %d/%d" % [String(entry[0]), int(d.current), int(d.required)])
	if rows.is_empty():
		rows.append("  [ ] something the checklist knows about and this button does not.")
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

## Type sigil + accent per prop, so the flavor popup reads as a catalogued object
## in a system rather than a floating paragraph. Sigils are deliberately plain
## Latin-1/ASCII: they render in every font this project can fall back to.
const PROP_SIGIL := {
	"kitchen": "≈", "code": ">_", "hardware": "#", "paper": "¶",
	"money": "€", "people": "@", "incident": "!", "nature": "*", "data": "§",
}

## prop id -> category. Anything unlisted falls back to "data".
const PROP_KIND := {
	"prop_fridge": "kitchen", "prop_coffee": "kitchen", "prop_bed": "kitchen",
	"prop_plant": "nature", "prop_sponsor": "nature", "prop_issue": "nature",
	"prop_terminal": "code", "prop_monitors": "code", "prop_sticker": "code",
	"prop_leftpad": "code", "prop_accepted": "code",
	"prop_router": "hardware", "prop_server": "hardware", "prop_rig": "hardware",
	"prop_fan": "hardware",
	"prop_whiteboard": "paper", "prop_lockfile": "paper", "prop_runbook": "paper",
	"prop_mission": "paper", "prop_kanban": "paper", "prop_gravestone": "paper",
	"prop_invoice": "money", "prop_pricing": "money", "prop_api_stall": "money",
	"prop_vault": "money",
	"prop_status_page": "incident", "prop_pager": "incident",
	"prop_node_modules": "data", "prop_dashboard": "data",
}

## Environmental comedy props. [E] on them for a laugh; pure flavor, no stakes
## (except the ones that gently cost Will To Live, because relatability).
##
## FORMAT: id -> [title, body_1, body_2, body_3, ...]. Extra bodies are the
## repeat-interaction escalation — the ladder is authored so that visit 1 is a
## joke, visit 3 is a joke that has noticed you, and visit 6 is openly worried
## about you. The last body repeats once you run out, but the visit counter keeps
## climbing in the popup subtitle, and `_state_note()` keeps reacting to the run.
const FLAVOR := {
	"prop_fridge": ["Fridge",
		"Contents: 14 energy drinks, one (1) sad baby carrot, and a yogurt that expired during the last framework migration.\n\nNutrition: technically.",
		"You open it again. The carrot has not improved. The yogurt has developed opinions.\n\nThe little light comes on. Something in you does not.",
		"Third visit. A refrigerator is not a backlog. Nothing new has been deployed to it.\n\nThe yogurt is now the most senior thing in this apartment.",
		"You are using a fridge as a break from a screen you chose to look at.\n\nThe carrot would like to be listed as a co-author.",
		"You stand in the cold light with the door open, thinking about the architecture.\n\nThis is the closest thing to fresh air you will get tonight.",
		"Sixth visit. There is nothing in here. There was nothing in here the last five times.\n\nYou are not hungry. You are looking for a decision that someone else has already made."],
	"prop_plant": ["Potted Plant",
		"Status: DEPRECATED.\nLast watered: v0.3.0.\nStill more alive than the roadmap.",
		"You check on it again. It has not photosynthesised in your absence.\n\nIt has, however, outlived two side projects and one startup.",
		"The plant does not need attention. The plant needs water.\n\nThese are famously not the same thing, as several of your relationships could confirm.",
		"A single new leaf. Unprompted. Unearned. Not attributable to anything you did.\n\nThat is the only good news in this apartment and you should take it.",
		"You water it. Immediately, obviously, far too much.\n\nEvery system you touch tonight has the same failure mode and it is 'all at once, at the end'.",
		"Sixth check-in. It is a plant. It cannot tell you what to build.\n\nIt can tell you it is 3AM and something in this room needs looking after, and it is being generous about which."],
	"prop_bed": ["Bed",
		"It whispers: 'Sleep...'\nYou: 'Not during a hackathon.'\nThe bed has heard this lie before.",
		"The bed says nothing this time. It has moved to passive resistance.\n\nThe pillow is holding a grudge and, somehow, a receipt.",
		"Third approach. The bed is now simply a large soft object you keep visiting and refusing.\n\nIt is 3AM. One of you is being unreasonable, and it is not the furniture.",
		"You sit on the edge of it for four seconds, which your body files as 'a full night'.\n\nYour body is being extremely diplomatic about this.",
		"You have negotiated with this bed five times. You have lost five times and also, somehow, not slept.\n\nThat is a rare outcome. Congratulations, technically.",
		"Sixth visit. The bed has stopped arguing.\n\nIt is just there, being the correct answer, waiting for you to finish being wrong."],
	"prop_coffee": ["Coffee Machine",
		"MISSION CRITICAL.\nUptime: 100%. Ships to prod flawlessly.\nUnlike literally everything else you have built.",
		"Cup four. It performs perfectly again — no standup, no roadmap, no retro.\n\nIt is the best engineer in this apartment and it knows it.",
		"You have now consumed enough caffeine to qualify as a distributed system.\n\nConsistency: eventual. Availability: technically. Partition tolerance: emotional.",
		"The machine has never once asked what the coffee is for.\n\nThis is why the relationship works.",
		"You notice you have been holding an empty cup for some minutes.\n\nThe machine noticed first. It said nothing. It is not that kind of machine.",
		"Sixth cup. At this point the coffee is not doing anything.\n\nYou are running on the ritual, which is fine, but you should know that is what is happening."],
	"prop_router": ["Router",
		"Four lights. One is blinking wrong.\nDNS: it's not DNS.\n...it's always DNS.\nEither way: somehow your fault.",
		"You look again. The wrong light is still blinking wrong.\n\nYou consider unplugging it for ten seconds. You know this will work. You resent that it will work.",
		"You unplugged it. It worked. No root cause was found, recorded, or ever will be.\n\nThat gesture is the entire discipline of networking.",
		"The blinking light has changed rhythm. You have no idea what the old rhythm meant either.\n\nSomewhere a firmware update happened without asking anyone.",
		"You have now inspected this router five times and learned nothing, which is a perfect score.\n\nRouters do not explain themselves. That is not a bug, it is a business model.",
		"Sixth inspection. The lights are fine. They have always been fine.\n\nYou are checking the network because it is the only part of tonight that might not be your fault."],
	"prop_terminal": ["Terminal",
		"$ npm audit\n\n847 vulnerabilities (312 high, 61 critical)\n0 addressed.\n\nConfidence: restored.",
		"$ npm audit fix\n\n3 fixed. 12 introduced. Four packages now demand a major version bump 'for security'.\n\nNet vulnerabilities: 856. Progress.",
		"$ npm audit fix --force\n\nThe terminal goes very quiet.\nSomewhere, a lockfile screams.\n\nYou close the tab and agree with yourself that this never happened.",
		"$ git status\n\n47 modified files. None staged. One of them is a .env you have opened 'just to check' nine times tonight.\n\nDo not commit the .env. You have committed the .env.",
		"$ history | wc -l\n\n2,904.\n\nThe last 300 are the same four commands in different orders, which is either debugging or a prayer.",
		"$ echo 'why'\nwhy\n\nThe terminal did exactly what you asked, instantly, without judgement, for the ten-thousandth time tonight.\n\nIt is the only thing in this room with a clean record."],
	"prop_whiteboard": ["Whiteboard",
		"'MVP ARCHITECTURE'\nApproximately 38 arrows. Two boxes labeled '???'. One labeled 'here be dragons'.\n\nA red arrow loops back to itself. Nobody remembers why.",
		"You study it properly this time. Two of the boxes were drawn by someone who has since left the company.\n\nThe red loop is load-bearing. Do not erase the red loop.",
		"You have now looked at this whiteboard for longer than anyone spent designing it.\n\nSomeone has added, in a different pen, in the corner: 'we knew'.",
		"A new box has appeared overnight, in your handwriting, labelled 'temp'.\n\nEverything else on the board now points at it.",
		"You try to redraw it cleanly. Halfway through you realise the mess was carrying information the clean version cannot.\n\nYou put the marker down. The mess wins. The mess always wins.",
		"Sixth review. The diagram has stopped describing the system and started describing the decisions.\n\nEvery arrow is a night like this one. There are a lot of arrows."],
	"prop_monitors": ["Battlestation",
		"Monitor 1: TOKEN BALANCE: dangerously low.\nMonitor 2: AI SUBSCRIPTIONS: 8 active.\nMonitor 3: MONTHLY SAVINGS FROM AI: -€713.\n\nThe math is not mathing.",
		"Monitor 2 has updated: 9 active subscriptions.\nYou do not remember the ninth. The ninth remembers you.\n\nIt renews on the 3rd.",
		"All three monitors now show the same dashboard, because you were 'consolidating'.\n\nIt is the dashboard nobody reads. It is beautifully rendered.",
		"Monitor 3 has been showing a loading spinner since you sat down.\n\nYou have stopped seeing it. It has not stopped spinning.",
		"You count 41 open tabs across three screens. Six are the same documentation page at different scroll positions.\n\nOne is a video you paused in March.",
		"Sixth look. Every screen in front of you is showing something that is technically your responsibility.\n\nNone of them is showing the thing you are actually meant to be building."],
	"prop_sticker": ["Laptop Lid",
		"Stickers: a raccoon, three defunct startups, and one that just says 'I USE ARCH BTW'.\n\nThe laptop runs, in fact, on spite.",
		"Under the raccoon there is an older sticker, half-peeled: a company that raised €40M and shipped a landing page.\n\nYou were employee eleven. You still have the hoodie.",
		"You count them again. Four of the six companies no longer exist.\n\nThe laptop outlasted all of them. So, technically, did you.",
		"There is a sticker from a conference you do not remember attending, for a database you have never used.\n\nIt is the most firmly attached one. Nothing removes it.",
		"You find a small, hand-cut sticker under the hinge that just says 'ship it'.\n\nYou have no memory of putting it there. It has been right the whole time.",
		"Sixth inventory. This lid is a résumé nobody asked for, in a format nobody accepts.\n\nIt is also the most honest CV you have ever produced."],
	"prop_server": ["Server Rack",
		"A tower of consumer GPUs held together by zip ties and denial.\nGPU 3 is at 94°C and 'fine'.\nIt is not fine. It is space-heater-in-July fine.",
		"GPU 3 is at 96°C. You add another zip tie.\n\nZip ties do not conduct heat away from anything. You knew this before you did it.",
		"GPU 3 has stopped reporting a temperature entirely.\n\nThis is either a sensor fault or the best news of the night. You decide not to investigate — investigating is how outages start.",
		"There is a cable in here going from the rack to the rack. Both ends. Same box.\n\nYou unplug one end. Two unrelated things stop working. You plug it back in.",
		"A fan you have never heard before starts up. You did not know there was a fifth fan.\n\nThe rack has been holding something in reserve this whole time.",
		"Sixth inspection. You built this. On purpose. In stages. Each of which was reasonable.\n\nThat is how every legacy system in history was built, and now you are in the club."],

	# --- Dependency District ---
	"prop_node_modules": ["node_modules/",
		"1.2 GB. Four (4) files you use; forty thousand you pray never break.\nIt has its own gravity now. Small moons orbit it.",
		"You look again. 1.4 GB. You have installed nothing in between.\n\nIt is growing. No explanation survives contact with a senior engineer.",
		"Somewhere in here is a package whose entire job is to check whether a number is a number.\n\nIt has 61 million weekly downloads and one very tired maintainer.",
		"You delete it and reinstall. It comes back 40 MB larger and one of the warnings is new.\n\nNobody knows what the new warning means. It will be in every install from now on.",
		"Fifth excavation. There are packages in here whose last release predates the framework you are using them with.\n\nThey work perfectly. Do not touch them."],
	"prop_leftpad": ["left-pad",
		"Eleven lines of code.\nOnce took down half the internet.\nStill more reliable than your auth service.",
		"Eleven lines. You could write it in ninety seconds.\n\nYou will not. Nobody will. That is the actual lesson and the entire industry refuses it.",
		"It sits there, small and calm, having caused more downtime than every architecture review in history has prevented.",
		"You open it. It is genuinely well written. Clear names, no cleverness, does one thing.\n\nMost of your code is not this good. You close the file quietly."],
	"prop_lockfile": ["package-lock.json",
		"47,000 lines. Nobody has read it. Nobody ever will.\nIt is load-bearing folklore. Do not 'git blame' it. It blames back.",
		"You open it. Line 12,004 references a package published by an account that has not posted since 2019.\n\nYou close it.",
		"You have now looked at the lockfile three times without changing anything, which remains the correct and only way to interact with a lockfile.",
		"Someone on your team regenerated it once, in 2023. The diff was 19,000 lines and the PR is still open.\n\nIts title is 'chore: lockfile'. Its comments are a war."],
	# --- API Bazaar ---
	"prop_api_stall": ["API Reseller Stall",
		"'FREE tier: 3 requests/month.\nPRO tier: also 3, but you feel better about it.'",
		"The sign has changed: 'ENTERPRISE tier: contact sales.'\n\nThere is no contact. There is no sales. There is a form.",
		"'FREE tier discontinued. Existing users grandfathered until Friday.'\n\nIt is Friday. It is always Friday here.",
		"A new tier has appeared between PRO and ENTERPRISE. It is called PRO+.\n\nIt is PRO, plus an invoice."],
	"prop_status_page": ["Status Page",
		"✅ All systems operational.\n(This page is cached. From June. It is not June.)",
		"✅ All systems operational.\n\nBelow, in 9pt grey: 'Investigating elevated error rates.' Posted four hours ago. Never updated.",
		"The status page is now itself down.\n\nFor the first time all week, it is accurate.",
		"A postmortem has been published. It is 400 words long and contains no verbs with a subject.\n\n'Errors were observed.' By whom? By everyone. For six hours."],
	"prop_pricing": ["Pricing Board",
		"Pay-as-you-go!\nGo where, exactly?\n...bankrupt. The answer is bankrupt.",
		"A new line item has appeared: 'egress'.\n\nNobody has ever budgeted for egress. Egress has budgeted for you.",
		"The board now reads 'Contact us for pricing', which is this industry's way of saying 'we saw your funding round'.",
		"There is a footnote. The footnote has a footnote.\n\nThe second footnote says 'subject to change'. It is the only honest thing on the board."],
	# --- Stack Overflow Ruins ---
	"prop_gravestone": ["Gravestone",
		"Here lies a Question.\n'Closed as opinion-based.'\n2011 – 2011. It had so much to ask.",
		"Beside it, a smaller stone: 'Closed as too broad.'\n\nThe question was four words long.",
		"A third stone, freshly cut: 'Duplicate of a question that was itself closed as a duplicate.'\n\nSomewhere, a loop closes.",
		"The newest stone has no epitaph, only a date from this year and the words 'answered by a model'.\n\nNobody came to the funeral. Everyone uses the answer."],
	"prop_accepted": ["Accepted Answer",
		"Score: 4,201. Written in a language deprecated in 2014.\nStill the #1 result. Still the only thing that works.",
		"Top comment, 340 upvotes: 'This no longer works.'\nReply, 890 upvotes: 'It does if you don't upgrade.'\n\nThis is the state of the art.",
		"The author's profile: last seen nine years ago.\n\nThey solved your problem before you had it and then left, which is the most gracious thing anyone has ever done for you.",
		"You scroll to the bottom. There is a better answer, posted two years later, with six votes.\n\nIt will never be seen again. That is the whole tragedy of ranking."],
	# --- Cloud District ---
	"prop_invoice": ["Cloud Invoice",
		"This month: 'successful adoption.'\n€4,207.\nYou ran one (1) cron job. It printed 'hello'.",
		"The itemised breakdown arrives: 340 line items.\n\nThe largest is called 'Other'. 'Other' is €2,900.",
		"You open a support ticket about the bill.\n\nThe reply recommends engaging a solutions architect. The solutions architect is billable.",
		"There is a credit on the account for €12.40, issued as an apology for an outage that cost you a customer.\n\nIt expires in 30 days."],
	"prop_dashboard": ["Cloud Dashboard",
		"94 services provisioned.\nYou use 2.\nThe other 92 are 'strategic'. And billing.",
		"You try to delete one. It has six dependencies. Each of those has four.\n\nYou close the tab. This is precisely how the 92 became 92.",
		"There is a service here you have never heard of, created by a Terraform run in March, costing €41 a month, that nobody can identify.\n\nIt is named 'temp'.",
		"You find the console for turning things off. It is three menus deep and requires typing the resource name to confirm.\n\nThe console for turning things on is on the front page and has a large blue button."],
	# --- GPU Mines ---
	"prop_rig": ["Mining Rig",
		"Hashing? Training? Rendering?\nHonestly nobody remembers anymore.\nIt is warm and it is expensive. That much is certain.",
		"A sticky note on the side reads: 'DO NOT STOP — running since Feb'.\n\nNo signature. No job name. No logs.",
		"You hold a hand near it. The heat is genuinely impressive.\n\nIn winter this rig is a heating subsidy. In July it is a moral question.",
		"You finally trace the job. It is a training run for a model that shipped in April and was replaced in May.\n\nNobody turned it off. Turning it off requires a decision, and decisions require a meeting."],
	"prop_fan": ["Cooling Fan",
		"Decibels: jet engine.\nEffectiveness: largely spiritual.",
		"Someone has aimed it at the thermometer rather than at the hardware.\n\nThe metric improved immediately. This is called optimising for the KPI.",
		"It has run so long you no longer consciously hear it.\n\nYou will hear it tonight, in bed, forever.",
		"There is a second fan behind the first, pointed the other way.\n\nThey have been cancelling each other out since installation. The room is, on average, correct."],
	# --- Open Source Wildlands ---
	"prop_sponsor": ["Sponsor Button",
		"11 years. 40M downloads/month.\nSponsorship: $7/month and one (1) thumbs-up react.\nThe maintainer has seen things.",
		"A Fortune 500 runs this package in production.\n\nThey have not sponsored. They have filed three issues this quarter.",
		"The README now opens with: 'This project is maintained in my evenings. Please be kind.'\n\nThe newest issue is titled 'URGENT'.",
		"Someone sponsored $5 with the note 'thanks, this saved my launch'.\n\nThe maintainer has that note pinned. It has been there for four years."],
	"prop_issue": ["Open Issue #4092",
		"'URGENT: doesn't work.'\nNo repro. No version. No logs. No mercy.\nFiled 3 years ago. Assigned to: nobody. Ever.",
		"Someone has commented: '+1'.\nSomeone else: 'any update?'\nThe maintainer, once, two years ago: 'could you share a reproduction?'\n\nSilence.",
		"Auto-closed by a stale-bot, reopened by a stranger, auto-closed again.\n\nIt will outlive the project. It may outlive the language.",
		"A new comment, from an account created today: 'Still broken in 2026. Unbelievable that this is not fixed.'\n\nThe fix has been in a draft PR since 2023, waiting on a review from one person."],
	# --- Corporate Enterprise ---
	"prop_mission": ["Mission Statement",
		"'To synergize AI-first paradigms at hyperscale.'\nFramed. Backlit. Gold leaf.\nMeans nothing. Cost €40k.",
		"A smaller plaque below credits the agency.\n\nThe agency's own website is one page with a video of a drone over a beach.",
		"You read it a third time and, for one horrible second, understand it.\n\nThis is the most alarming thing that has happened to you all night.",
		"The previous mission statement is still visible as a rectangle of unfaded paint behind the frame.\n\nIt was two words long and everyone could remember it."],
	"prop_kanban": ["Kanban Board",
		"'In Progress': 47 tickets.\n'Done': 0.\n'Blocked': everything, spiritually.",
		"A new column has appeared: 'In Progress (Actually)'.\n\nIt holds three tickets. All three are also still in 'In Progress'.",
		"Someone has added a column called 'Won't Fix (For Now)'.\n\nIt is the only column with velocity.",
		"The oldest ticket is from a person who left two years ago. It is titled 'quick fix' and has 61 comments.\n\nNobody will close it. Closing it would mean deciding something."],
	# --- Production ---
	"prop_pager": ["On-Call Pager",
		"3 missed pages.\nOne during your own wedding.\nIt buzzes again. It always buzzes again.",
		"You check the escalation policy.\nPrimary: you.\nSecondary: you.\nManager escalation: also, somehow, you.",
		"It buzzes. False alarm — a healthcheck that has been broken for six months.\n\nNobody will fix it, because fixing it means admitting it exists.",
		"You silence it. It buzzes eleven seconds later with the same alert and a new incident number.\n\nThe system is working exactly as designed by someone who has never been on call."],
	"prop_runbook": ["Incident Runbook",
		"Step 1: Don't panic.\nStep 2: Panic.\nStep 3: Blame DNS.\nStep 4: It was DNS.",
		"Step 5, added later in different handwriting: 'If step 4 fails, restart the thing. You know the thing.'\n\nYou do know the thing.",
		"The last page is blank except for one line:\n'If you are reading this at 4AM, it is not your fault, and it is your problem.'\n\nSomebody cared once.",
		"There is a runbook for writing runbooks. It is 40 pages. It has never been followed, including by itself."],
	# --- Token Vault ---
	"prop_vault": ["Token Vault",
		"Balance: enough for one (1) frontier prompt, OR a week of the local 7B.\nChoose wisely. The vault is judging you.",
		"A small brass plate reads: 'ESTIMATED SPEND THIS MONTH'.\n\nThe number is written in pencil and has been erased four times.",
		"You stare into the vault. The vault stares back and quietly recalculates your burn rate.\n\nIt does not like the trend.",
		"There is a second, smaller vault inside the vault, labelled 'reserved capacity'.\n\nIt is empty. It has always been empty. It is reserved."],
}

## Repeat-interaction escalation: walk the body list, then let the visit counter
## and the run-state note carry the joke once the list runs out.
func _flavor_for(id: String) -> void:
	var f: Array = FLAVOR[id]
	var visits: int = _Comedy.bump("prop:%s" % id)
	var bodies: Array = f.slice(1)
	if bodies.is_empty():
		bodies = ["..."]
	var idx: int = clampi(visits - 1, 0, bodies.size() - 1)
	var body := String(bodies[idx])
	var note := _state_note(id, visits)
	if note != "":
		body += "\n\n" + note
	_flavor(String(f[0]), body, _Comedy.visit_note(visits))

## Props react to the RUN, not just to how many times you have poked them. The
## fridge empties as you raid it, the whiteboard accumulates the architecture you
## actually chose, the plant tracks your technical debt, the vault does the math.
##
## Returns "" when this prop has nothing state-specific to say — most visits.
func _state_note(id: String, visits: int) -> String:
	var debt := int(ResourceManager.get_value("technical_debt"))
	var tokens := int(ResourceManager.get_value("tokens"))
	var stability := int(ResourceManager.get_value("stability"))
	var wtl := int(ResourceManager.get_value("will_to_live"))
	var deaths: int = GameManager.death_count
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var ridiculous: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0
	var tiers := int(DreamAppManager.get_totals().get("total_tiers", 0))
	var cyc: int = CycleManager.cycle if CycleManager else 1

	match id:
		"prop_fridge":
			var drinks: int = maxi(14 - visits, 0)
			if drinks == 0:
				return "STOCK: 0 energy drinks. 1 carrot. The carrot is now the plan."
			if wtl <= 40:
				return "STOCK: %d energy drinks left, and a body that has started sending you deprecation warnings." % drinks
			return "STOCK: %d energy drinks left." % drinks
		"prop_plant":
			if debt >= 60:
				return "SOIL REPORT: technical debt %d. Even the plant has started routing around you." % debt
			if debt >= 30:
				return "SOIL REPORT: technical debt %d. It is drooping in sympathy, or in judgement." % debt
			return ""
		"prop_bed":
			if deaths >= 3:
				return "TONIGHT: %d respawns, 0 hours of sleep. Ctrl+Z works on your body. It does not work on the tiredness." % deaths
			if visits >= 3:
				return "SLEPT: 0 nights.\nSAT ON EDGE OF BED THINKING: %d times." % visits
			return ""
		"prop_router":
			if stability <= 40:
				return "LINK: fine. Stability: %d. It is, for once, genuinely not the network." % stability
			return ""
		"prop_terminal":
			if debt >= 40:
				return "$ debt --report\n%d units of technical debt. Every upgrade now costs about %d%% more. The terminal is not editorialising. The terminal never editorialises." % [debt, int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))]
			return ""
		"prop_whiteboard":
			var arrows: int = 38 + ridiculous * 7 + tiers * 2
			var decided: int = arch.size()
			if decided > 0:
				return "CURRENT DIAGRAM: %d arrows, %d architecture decisions made tonight, 0 of them written down anywhere else." % [arrows, decided]
			return "CURRENT DIAGRAM: %d arrows. No architecture decisions recorded yet, which the board is treating as a decision." % arrows
		"prop_monitors":
			var subs: int = 8 + cyc
			if tokens < 30:
				return "MONITOR 1: %d tokens.\nMONITOR 2: %d AI subscriptions.\nThe second number has never once gone down." % [tokens, subs]
			return "MONITOR 2: %d active subscriptions. You can name six." % subs
		"prop_server":
			if agents > 0:
				return "RACK LOAD: %d autonomous agent(s) currently running on this hardware, unsupervised, confidently." % agents
			return ""
		"prop_sticker":
			if cyc >= 3:
				return "This laptop has now survived %d quota resets tonight. It is not proud. It is not anything. It is a laptop." % cyc
			return ""
		"prop_node_modules", "prop_lockfile":
			if debt >= 40:
				return "DEPENDENCY HEALTH: technical debt %d. Somewhere in here is the reason. It will not be found tonight." % debt
			return ""
		"prop_invoice", "prop_dashboard":
			if arch.get("hosting") == "cloud":
				return "BILLING NOTE: you chose the cloud. The cloud has chosen you back, monthly, in perpetuity."
			return "BILLING NOTE: you are not even hosted here and it still found a way to invoice you €0.03 for a DNS lookup."
		"prop_pager", "prop_runbook":
			if stability <= 40:
				return "CURRENT STABILITY: %d. The pager is not asleep. The pager has never been asleep." % stability
			return ""
		"prop_vault":
			var cheapest := _cheapest_upgrade_cost()
			if cheapest > 0 and tokens < cheapest:
				return "LEDGER: %d tokens held. Cheapest remaining upgrade: %d. You are %d short, and the vault has done that subtraction for you." % [tokens, cheapest, cheapest - tokens]
			return "LEDGER: %d tokens held, %d upgrades bought. The vault would like these two numbers to be more related." % [tokens, tiers]
		"prop_mission", "prop_kanban":
			if ridiculous >= 3:
				return "ARCHITECTURE RIDICULOUSNESS: %d. Corporate would like to feature your design in a case study." % ridiculous
			return ""
	return ""

## The coffee machine was, until now, the only prop in the apartment that told a
## joke and did nothing: ResourceManager.drink_coffee() existed with no caller,
## while the [H] guide cheerfully instructed the player to "find the coffee
## machine and press [E]". Now that instruction is true. The flavor text still
## escalates; it just also reports exactly what the machine did to your focus.
func _coffee_break() -> void:
	var visits: int = _Comedy.bump("prop:prop_coffee")
	var bodies: Array = FLAVOR["prop_coffee"].slice(1)
	var body := String(bodies[clampi(visits - 1, 0, bodies.size() - 1)])
	var before := int(ResourceManager.get_value("focus"))
	if ResourceManager.drink_coffee():
		body += "\n\nPOURED: 1 cup. Focus %d -> %d. Cups left in the flat: %d." % [
			before, int(ResourceManager.get_value("focus")),
			int(ResourceManager.get_value("coffee"))]
	else:
		body += "\n\nPOURED: nothing. You are out of coffee. The machine is willing; the supply chain is not."
	_flavor(String(FLAVOR["prop_coffee"][0]), body, _Comedy.visit_note(visits))

## Cheapest next upgrade cost in tokens, or 0 if everything is bought.
func _cheapest_upgrade_cost() -> int:
	var best := 0
	for b in DreamAppManager.BRANCHES:
		if DreamAppManager.get_next_upgrade(b).is_empty():
			continue
		var cost: Dictionary = DreamAppManager.get_effective_cost(b)
		var tk := int(cost.get("tokens", 0))
		if tk <= 0:
			continue
		if best == 0 or tk < best:
			best = tk
	return best

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
	popup.sigil_text = _sigil_for(interact_id)
	popup.accent_color = _accent_for(interact_id)
	_show_overlay(popup)

func _sigil_for(id: String) -> String:
	return String(PROP_SIGIL.get(String(PROP_KIND.get(id, "data")), "§"))

## Category accent, so a fridge and an on-call pager never feel like the same
## kind of news. Colours are straight from the VISUAL_BIBLE master palette.
func _accent_for(id: String) -> Color:
	match String(PROP_KIND.get(id, "data")):
		"kitchen": return _GameTheme.AMBER
		"code": return _GameTheme.CYAN
		"hardware": return Color("#FF6B2D")
		"paper": return _GameTheme.VIOLET
		"money": return _GameTheme.GOLD
		"people": return _GameTheme.BLUE
		"incident": return _GameTheme.RED
		"nature": return _GameTheme.ACID
	return _GameTheme.CYAN

## System messages ride the same styled popup as the flavor props: it lives under
## the HUD CanvasLayer (so death clears it), it pauses while you read, and it
## closes on [E]. The old AcceptDialog did none of those things.
func _show_message(text: String, title: String = "System Message") -> void:
	_flavor(title, text)
